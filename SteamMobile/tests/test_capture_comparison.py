#!/usr/bin/env python3
"""Synthetic arithmetic tests, never device benchmark results."""
import copy
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from compare_captures import summarize, compare


def report():
    return {'schema': 1, 'measurement': 'DXMT aggregate present counter', 'build': 'fixture',
            'label': 'test scene', 'durationSeconds': 40, 'samples': [
                {'intervalSeconds': 1.0, 'presentDelta': 60, 'counterReset': False,
                 'delayedSample': False, 'appActive': True, 'thermalState': 0,
                 'pacingMode': 2, 'lowPowerMode': False, 'physicalFootprintBytes': 1024}
                for _ in range(40)]}


class CaptureComparison(unittest.TestCase):
    def test_rate_uses_elapsed_time_not_average_of_rates(self):
        data = report()
        data['samples'][0]['intervalSeconds'] = 2.0
        self.assertAlmostEqual(summarize(data)['presents_per_second'], 2400 / 41)

    def test_gaps_and_resets_are_excluded_but_zero_rate_is_valid(self):
        data = report()
        data['samples'][0]['delayedSample'] = True
        data['samples'][1]['counterReset'] = True
        data['samples'][2]['appActive'] = False
        data['samples'][3]['presentDelta'] = 0
        result = summarize(data)
        self.assertEqual(result['excluded_samples'], 3)
        self.assertEqual(result['presents'], 36 * 60)

    def test_incomparable_runs_have_no_improvement_claim(self):
        before = report(); after = copy.deepcopy(before)
        after['samples'][0]['pacingMode'] = 1
        self.assertIsNone(compare(before, after)['throughput_change_percent'])
        self.assertEqual(compare(before, before)['throughput_change_percent'], 0)

    def test_no_presents_or_invalid_interval(self):
        data = report()
        for sample in data['samples']: sample['presentDelta'] = 0
        self.assertIsNone(compare(data, data)['throughput_change_percent'])
        data['samples'][0]['intervalSeconds'] = float('nan')
        with self.assertRaises(ValueError): summarize(data)


if __name__ == '__main__': unittest.main()
