#!/usr/bin/env python3
"""Generates the benchmark data: 20 theatres x 250 days x 4 showtimes = 20,000 showtimes,
200 seats each, 70% sold in bookings of 1-4 seats (about 2.8 million tickets).
Usage: generate-data.py OUTPUT_DIR   (writes CSV and query files; deterministic)"""
import datetime
import os
import random
import sys

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
random.seed(7)
theatres = [(b, t) for b in range(1, 6) for t in range(1, 5)]
dates = [datetime.date(2026, 1, 1) + datetime.timedelta(d) for d in range(250)]
times = ['10:00:00', '13:00:00', '16:00:00', '19:00:00']
SEATS = 200

shows, sid = [], 0
for b, t in theatres:
    for d in dates:
        for tm in times:
            sid += 1
            shows.append((sid, b, t, d, tm))

bid, rows = 0, 0
with open(f'{out}/A.csv', 'w') as fa, open(f'{out}/B.csv', 'w') as fb, open(f'{out}/B2.csv', 'w') as fb2:
    for sid, b, t, d, tm in shows:
        sold = random.sample(range(1, SEATS + 1), int(SEATS * 0.7))
        i = 0
        while i < len(sold):
            bid += 1
            n = random.choice([1, 2, 2, 3, 4])
            for s in sold[i:i + n]:
                fa.write(f'{b},{t},{d},{tm},{s},{bid}\n')   # A : composite key
                fb.write(f'{sid},{s},{bid}\n')               # B : showtime_id only
                fb2.write(f'{sid},{b},{t},{s},{bid}\n')      # B2: showtime_id + branch/theatre kept
                rows += 1
            i += n
print(f'{rows} tickets, {bid} bookings, {len(shows)} showtimes')

random.seed(1)
pick = random.sample(shows, 300)
bookings = random.sample(range(1, bid), 300)
with open(f'{out}/qa_map.sql', 'w') as qa, open(f'{out}/qb_map.sql', 'w') as qb, open(f'{out}/qb2_map.sql', 'w') as qb2:
    for sid, b, t, d, tm in pick:
        qa.write(f"SELECT seat_id FROM ticket_a WHERE branch_id={b} AND theatre_id={t} AND showtime_date='{d}' AND showtime_time='{tm}';\n")
        qb.write(f"SELECT seat_id FROM ticket_b WHERE showtime_id={sid};\n")
        qb2.write(f"SELECT seat_id FROM ticket_b2 WHERE showtime_id={sid};\n")
with open(f'{out}/qa_del.sql', 'w') as da, open(f'{out}/qb_del.sql', 'w') as db, open(f'{out}/qb2_del.sql', 'w') as db2:
    for k in bookings:
        da.write(f'DELETE FROM ticket_a WHERE booking_id={k};\n')
        db.write(f'DELETE FROM ticket_b WHERE booking_id={k};\n')
        db2.write(f'DELETE FROM ticket_b2 WHERE booking_id={k};\n')
