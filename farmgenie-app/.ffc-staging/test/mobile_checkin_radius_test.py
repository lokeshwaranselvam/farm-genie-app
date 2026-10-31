"""Execute the supplied Server Script with mocked ERP I/O for both punch directions."""
from datetime import datetime, timedelta
from pathlib import Path
from types import SimpleNamespace
import unittest

SCRIPT = (Path(__file__).parents[1] / 'erp_api/attendance/attendance_api.py').read_text()


class Row(dict):
    __getattr__ = dict.get


def run_request(action='status', direction='IN', distance=0, radius=100):
    now = datetime(2026, 10, 31, 12)
    inserted = []
    response = {}
    employee = Row(name='EMP-1', employee_name='Employee', grade='', custom_is_operation=0)

    def sql(query, values, **kwargs):
        if 'FROM `tabEmployee`' in query:
            return [employee]
        if 'AS distance_m' in query:
            return [Row(distance_m=distance)]
        if 'time ASC' in query and direction == 'OUT':
            return [Row(name='IN-1', log_type='IN', time=now - timedelta(hours=1))]
        return []

    def fail(message):
        raise ValueError(message)

    def document(fields):
        return SimpleNamespace(name='NEW-1', insert=lambda **kwargs: inserted.append(fields))

    frappe = SimpleNamespace(
        session=Row(user='employee@example.test', csrf_token='csrf'),
        form_dict=Row(action=action, log_type=direction, attendance_security_token='csrf',
                      expected_last_checkin='IN-1' if direction == 'OUT' else '',
                      latitude=13.0549854, longitude=80.1545772,
                      custom_office_type='Head Office - Vanagaram'),
        response=response,
        throw=fail,
        db=SimpleNamespace(sql=sql, commit=lambda: None, rollback=lambda: None),
        utils=SimpleNamespace(
            cint=int, now_datetime=lambda: now, getdate=lambda value: value.date(),
            get_datetime=lambda value: value if isinstance(value, datetime) else datetime.fromisoformat(value),
            add_days=lambda value, days: value + timedelta(days=days)),
        make_get_request=lambda *args, **kwargs: {'display_name': 'Office'},
        get_meta=lambda _: SimpleNamespace(get_field=lambda _: None),
        get_doc=document,
    )
    configured = SCRIPT.replace('geofence_radius_meters = 100', f'geofence_radius_meters = {radius}')
    exec(compile(configured, 'attendance_api.py', 'exec'), {'frappe': frappe})
    return response, inserted


class MobileCheckinRadiusTest(unittest.TestCase):
    def test_status_publishes_server_configuration(self):
        for radius in (100, 275):
            response, inserted = run_request(radius=radius)
            self.assertEqual(response['message']['geofence_radius_meters'], radius)
            self.assertEqual(inserted, [])

    def test_both_directions_enforce_same_configured_radius(self):
        for direction in ('IN', 'OUT'):
            for radius in (100, 275):
                for distance in (radius - 1, radius, radius + 1):
                    with self.subTest(direction=direction, radius=radius, distance=distance):
                        response, inserted = run_request('checkin', direction, distance, radius)
                        if distance <= radius:
                            self.assertEqual(response['message']['status'], 'success')
                            self.assertEqual(inserted[0]['log_type'], direction)
                        else:
                            self.assertEqual(response['http_status_code'], 400)
                            self.assertIn(f'within {radius} metres', response['message']['message'])
                            self.assertEqual(inserted, [])


if __name__ == '__main__':
    unittest.main()
