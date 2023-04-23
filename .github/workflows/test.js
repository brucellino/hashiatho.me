import http from 'k6/http';
import { sleep } from 'k6';

export const options = {
  duration: '1m',
  vus: 1000,
  thresholds: {
    http_req_failed: ['rate<0.001'], // http errors should be less than 1%
    http_req_duration: ['p(95)<150'], // 95 percent of response times must be below 100ms
    http_req_duration:
  },
};

export default function () {
  const res = http.get('https://hashiatho.me');
  sleep(1);
}
