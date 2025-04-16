import os
import unicodedata
import requests


def convert_to_ascii(text):
    return ''.join(c if ord(c) < 128 else unicodedata.normalize('NFKD', c).encode('ascii', 'ignore').decode('ascii') for c in text)


def get_public_ip(extra=False):
    # Try ip-api.com first
    try:
        r = requests.get("http://ip-api.com/json", timeout=5)
        data = r.json()
        public_ip = data['query']
        if extra:
            country = data.get('country', 'Unknown')
            return {
                "ip": public_ip,
                "country": country
            }
        else:
            return public_ip
    except Exception:
        # Try reallyfreegeoip.org second
        try:
            r = requests.get("https://reallyfreegeoip.org/json/", timeout=5)
            data = r.json()
            public_ip = data['ip']
            if extra:
                country = data.get('country_name', 'Unknown')
                return {
                    "ip": public_ip,
                    "country": country
                }
            else:
                return public_ip
        except Exception:
            # Try ipinfo.io last
            try:
                response = requests.get('https://ipinfo.io/json', timeout=5)
                data = response.json()
                public_ip = data['ip']
                if extra:
                    country = data.get('country', 'Unknown')
                    return {
                        "ip": public_ip,
                        "country": country
                    }
                else:
                    return public_ip
            except Exception:
                # Last resort fallback
                if extra:
                    return {
                        "ip": "unknown",
                        "country": "Unknown"
                    }
                else:
                    return "unknown"
