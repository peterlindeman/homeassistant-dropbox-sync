import argparse
import os

import requests
from dateutil.parser import parse
import pytz

BASE_URL = "http://supervisor/"
HEADERS = {"Authorization": "Bearer {0}".format(os.environ.get("SUPERVISOR_TOKEN"))}
 
def main(number_to_keep):

    backup_info = requests.get(BASE_URL + "backups", headers=HEADERS)
    backup_info.raise_for_status()

    backups = backup_info.json()["data"]["backups"]
    for backup in backups:
        d = parse(backup["date"])
        if d.tzinfo is None or d.tzinfo.utcoffset(d) is None:
            print("Naive DateTime found for backup {}, setting to UTC...".
                  format(backup["slug"]))
            backup["date"] = d.replace(tzinfo=pytz.utc).isoformat()
    backups.sort(key=lambda item: parse(item["date"]), reverse=True)
    keepers = backups[:number_to_keep]
    stale_backups = [snap for snap in backups if snap not in keepers]

    for backup in stale_backups:
        # call homeassistant API deletion
        res = requests.post(
            BASE_URL + "backups/" + backup["slug"] + "/remove",
            headers=HEADERS)
        if res.ok:
            print("[Info] Deleted backup {}".format(backup["slug"]))
            continue
        else:
            # log an error
            print("[Error] Failed to delete backup {}: {}".format(
                backup["slug"], res.status_code))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description='Remove old HomeAssistant backups.')
    parser.add_argument('number', type=int, help='Number of backups to keep')
    args = parser.parse_args()
    main(args.number)
