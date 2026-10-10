#!/usr/bin/env python3
"""Summarize real app captures without treating timer samples as frame times."""
import argparse
import json
import math
from pathlib import Path


def summarize(report):
    if report.get('schema') != 1 or 'DXMT aggregate present counter' not in report.get('measurement', ''):
        raise ValueError('Unsupported capture format')
    samples = report['samples']
    kept = []
    for sample in samples:
        interval = sample['intervalSeconds']
        if not isinstance(interval, (int, float)) or not math.isfinite(interval) or interval <= 0:
            raise ValueError('Invalid sampling interval')
        delta = sample.get('presentDelta')
        if delta is not None and (type(delta) is not int or delta < 0):
            raise ValueError('Invalid present count delta')
        if (delta is None or sample['counterReset'] or sample['delayedSample'] or
                not sample['appActive']):
            continue
        kept.append(sample)
    duration = sum(s['intervalSeconds'] for s in kept)
    presents = sum(s['presentDelta'] for s in kept)
    footprint = [s['physicalFootprintBytes'] for s in kept if s.get('physicalFootprintBytes') is not None]
    return {'build': report['build'], 'label': report['label'],
            'recorded_seconds': report['durationSeconds'], 'included_seconds': duration,
            'excluded_samples': len(samples) - len(kept), 'included_samples': len(kept),
            'presents': presents, 'presents_per_second': presents / duration if duration else None,
            'peak_physical_footprint_bytes': max(footprint) if footprint else None,
            'thermal_states': sorted(set(s['thermalState'] for s in kept)),
            'pacing_modes': sorted(set(s['pacingMode'] for s in kept)),
            'low_power_observed': any(s['lowPowerMode'] for s in kept),
            'limitations': report.get('limitations', [])}


def compare(before, after):
    baseline, candidate = summarize(before), summarize(after)
    reasons = []
    if not baseline['label'].strip() or baseline['label'] != candidate['label']:
        reasons.append('Game/scene/resolution/renderer labels are absent or different')
    if (len(baseline['pacing_modes']) != 1 or baseline['pacing_modes'] != candidate['pacing_modes']):
        reasons.append('Pacing mode differs or changed during a capture')
    if baseline['thermal_states'] != candidate['thermal_states']:
        reasons.append('Observed thermal conditions differ')
    if baseline['low_power_observed'] != candidate['low_power_observed']:
        reasons.append('Low Power Mode conditions differ')
    if min(baseline['included_seconds'], candidate['included_seconds']) < 30:
        reasons.append('Less than 30 seconds of active, timely samples')
    if not baseline['presents_per_second'] or not candidate['presents_per_second']:
        reasons.append('No nonzero present throughput measured in one or both captures')
    percent = None
    if not reasons:
        percent = 100 * (candidate['presents_per_second'] / baseline['presents_per_second'] - 1)
    return {'baseline': baseline, 'candidate': candidate,
            'throughput_change_percent': percent, 'comparison_issues': reasons,
            'interpretation': 'Aggregate present throughput only. Matching labels do not prove identical gameplay. '
                              'RAW includes skipped presents. No per-frame latency or 1% lows can be computed.'}


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('baseline', type=Path)
    ap.add_argument('candidate', type=Path)
    args = ap.parse_args()
    print(json.dumps(compare(json.loads(args.baseline.read_text()), json.loads(args.candidate.read_text())), indent=2))
