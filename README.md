# letsencrypt-totaluptime

Certbot manual auth hooks for DNS validation with Total Uptime

These scripts use Total Uptime's API to solve Let's Encrypt challenges by creating `_acme-challenge` TXT records. [About validation hooks](https://eff-certbot.readthedocs.io/en/stable/using.html#pre-and-post-validation-hooks)

## How to

Create an API role in Total Uptime with the following permissions:
- Dashboard, disabled
- Networking, disabled
- DNS, enabled
  - Information, Read
  - Domains, Read/Write/Create
  - Failover Pools, disabled
  - Geo zones, disabled
  - Monitors, disabled
  - Import/Export, disabled
  - Zone transfers, disabled
  - Reporting, disabled
- Account, disabled
- Modify password/2FA, disabled

Create a user with your new role and "API Account" checked.

[Install certbot](https://certbot.eff.org/instructions?ws=haproxy&os=ubuntufocal)

```sh
sudo snap install --classic certbot
sudo snap set certbot trust-plugin-with-root=ok
```

Install jq and curl

```sh
sudo apt install jq curl
```

Download the scripts

```sh
git clone https://github.com/nickadam/letsencrypt-totaluptime.git
```

Edit the `authenticator.sh` and `cleanup.sh` scripts. Add your Total Uptime API username and password to the top.

Create certs

```sh
sudo certbot certonly --preferred-challenges=dns --manual \
  --manual-auth-hook /home/ubuntu/letsencrypt-totaluptime/authenticator.sh \
  --manual-cleanup-hook /home/ubuntu/letsencrypt-totaluptime/cleanup.sh \
  --agree-tos \
  --eff-email \
  -m 'bob@example.com' \
  -d 'example.com' \
  -d '*.example.com' \
  -d 'example.org' \
  -d '*.example.org'
```

It's important to specify the full path to the scripts when you run certbot and leave the scripts in the same location when you are done. Certbot will call the same scripts to automatically renew certs 30 days before expiry.

If need be, you can modify the renewal process options in `/etc/letsencrypt/renewal/example.com.conf`.

The script waits for 5 minutes per domain to allow for propagation, be patient.

Sample output

```
Saving debug log to /var/log/letsencrypt/letsencrypt.log
Requesting a certificate for example.com and 3 more domains

Successfully received certificate.
Certificate is saved at: /etc/letsencrypt/live/example.com/fullchain.pem
Key is saved at:         /etc/letsencrypt/live/example.com/privkey.pem
This certificate expires on 2022-10-21.
These files will be updated when the certificate renews.
Certbot has set up a scheduled task to automatically renew this certificate in the background.

- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
If you like Certbot, please consider supporting our work by:
 * Donating to ISRG / Let's Encrypt:   https://letsencrypt.org/donate
 * Donating to EFF:                    https://eff.org/donate-le
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
```
