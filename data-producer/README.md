# data-producer

The **data source** for the [MQTT to Dashboard workshop](../mqtt-to-dashboard): an
MQTT broker plus a producer that publishes believable industrial sensor readings.
It's a standalone project — develop and deploy it independently of the workshop
consumer.

The producer emits one CSV reading per tag on a timer, to topics that encode the
plant hierarchy (a Unified Namespace):

```
topic:    workshop/<area>/<line>/<asset>/<metric>   e.g. workshop/plant1/line-a/mixer/temperature
payload:  tag_id,timestamp,value,quality            e.g. T-101,2026-07-06T12:00:00Z,71.3,192
```

## Layout

```text
data-producer/
  producer/                 # the generator (Python + paho-mqtt)
  broker/
    mosquitto.local.conf    # simple broker for local dev (anonymous, plaintext)
    mosquitto.conf          # hardened broker for public deploy (TLS + auth)
    aclfile                 # producer = read/write, attendee = read-only
  docker-compose.yml        # LOCAL: simple broker + producer
  docker-compose.server.yml # PUBLIC: hardened broker + producer
  setup.sh                  # provisions the public deployment (certs + passwords)
  .env.example              # local dev vars
  .env.server.example       # public deploy vars
```

---

## Local development

Run the feed by itself — a plaintext, anonymous broker on `localhost:1883` and the
producer publishing to it:

```bash
cp .env.example .env
docker compose up --build

# watch the raw stream:
docker exec -it data-producer-broker mosquitto_sub -t 'workshop/#' -v
```

To run the workshop consumer against it, point its `.env` at
`host.docker.internal:1883` (see [../mqtt-to-dashboard](../mqtt-to-dashboard)).

Iterate on the tag list and signal shapes in
[`producer/app/generator.py`](./producer/app/generator.py).

---

## Public deployment (shared broker for a workshop)

Host one broker + producer on a small public VM so up to ~100 attendees can
subscribe to the same live feed over TLS. Attendees run only the consumer.

A single small VM in a central region (e.g. `us-east-1`) is plenty — 100 MQTT
connections at a couple of messages per second is trivial load and continent-wide
latency is negligible. You do **not** need a multi-region setup.

### What the hardened broker enforces

- TLS on **8883** (the only port attendees use).
- A private plaintext listener on **1883** for the co-located producer — never
  published to the host, so it's unreachable from the internet.
- Auth required (anonymous refused) and an ACL: the `producer` account may
  publish; the shared `attendee` account is **read-only**, so nobody can inject
  fake readings.

### Prerequisites

1. A small Linux VM (1 vCPU / 1 GB) with a **public IP**, in a central region.
2. **Docker** with the Compose plugin.
3. A **DNS A record** (e.g. `broker.yourworkshop.com`) → the VM's IP. Let's
   Encrypt needs it for the cert; attendees connect to it.
4. Firewall / security group:
   - **8883/tcp** open to the world (keep open during the workshop)
   - **80/tcp** open only briefly, so Let's Encrypt can validate the domain
   - **22/tcp** for SSH, from your IP

### Setup

```bash
git clone https://github.com/timescale/tigerdata-devrel-workshops.git
cd tigerdata-devrel-workshops/data-producer

cp .env.server.example .env.server
# edit: set DOMAIN, CERTBOT_EMAIL, and strong PRODUCER_PASSWORD / ATTENDEE_PASSWORD

./setup.sh                 # passwords + Let's Encrypt cert + start the stack
# or, without a domain (testing):
./setup.sh --self-signed
```

`setup.sh` runs `mosquitto_passwd`, `certbot`, and `openssl` in containers, so
nothing extra installs on the VM. When it finishes it prints the exact `MQTT_*`
values to hand attendees.

### Verify

```bash
docker compose -f docker-compose.server.yml logs -f producer   # "published 6 readings"

# from your laptop — should stream messages:
mosquitto_sub -h broker.yourworkshop.com -p 8883 --capath /etc/ssl/certs \
  -u attendee -P '<attendee password>' -t 'workshop/#' -v

# attendees must NOT be able to publish (ACL denies it silently):
mosquitto_pub -h broker.yourworkshop.com -p 8883 --capath /etc/ssl/certs \
  -u attendee -P '<attendee password>' -t 'workshop/hack' -m 'nope'
```

### What attendees run

Give them these values, then they use `../mqtt-to-dashboard`:

```
MQTT_BROKER_HOST=broker.yourworkshop.com
MQTT_BROKER_PORT=8883
MQTT_TLS=true
MQTT_USERNAME=attendee
MQTT_PASSWORD=<shared attendee password>
```

### Operating notes

- **Cert renewal:** Let's Encrypt certs last 90 days — a non-issue for a one-off
  workshop. Long-running: `certbot renew`, copy the refreshed cert into
  `broker/certs/`, then `docker compose -f docker-compose.server.yml restart mqtt-broker`.
- **Rotate the attendee password:** edit `ATTENDEE_PASSWORD`, re-run `./setup.sh`,
  then `restart mqtt-broker`.
- **Scaling past ~100:** raise `max_connections` in `broker/mosquitto.conf`. One
  Mosquitto handles thousands; only cluster (e.g. EMQX) at a very different scale.
- **Secrets** (`.env`, `.env.server`, `broker/passwd`, `broker/certs/`) are
  git-ignored — never commit them.
