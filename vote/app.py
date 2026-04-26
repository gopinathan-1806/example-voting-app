from flask import Flask, render_template, request, make_response, g, redirect, url_for
from redis import Redis
import os
import socket
import random
import json
import logging
from datetime import datetime, timezone

hostname = socket.gethostname()

app = Flask(__name__)

gunicorn_error_logger = logging.getLogger('gunicorn.error')
app.logger.handlers.extend(gunicorn_error_logger.handlers)
app.logger.setLevel(logging.INFO)

def get_redis():
    if not hasattr(g, 'redis'):
        redis_host = os.getenv('REDIS_HOST', 'redis')
        g.redis = Redis(host=redis_host, db=0, socket_timeout=5)
    return g.redis

@app.route("/", methods=['POST', 'GET'])
def hello():
    voter_id = request.cookies.get('voter_id')
    if not voter_id:
        voter_id = hex(random.getrandbits(64))[2:-1]

    vote = None
    voter_name = ''

    if request.method == 'POST':
        redis = get_redis()
        vote = request.form.get('vote')
        voter_name = request.form.get('voter_name', '').strip()

        if vote in ('a', 'b', 'c'):
            if voter_name:
                voter_id = voter_name

            voted_at = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')

            data = json.dumps({
                'voter_id': voter_id,
                'voter_name': voter_name,
                'vote': vote,
                'voted_at': voted_at
            })

            redis.rpush('votes', data)
            app.logger.info('Received vote for %s from %s', vote, voter_name)

            resp = make_response(redirect(url_for('hello')))
            resp.set_cookie('voter_id', voter_id)
            resp.set_cookie('voter_name', voter_name)
            resp.set_cookie('has_voted', 'yes')
            return resp

    has_voted = request.cookies.get('has_voted')
    voter_name = request.cookies.get('voter_name', '')

    if has_voted:
        vote = has_voted

    resp = make_response(render_template(
        'index.html',
        vote=vote,
        hostname=hostname,
        voter_name=voter_name
    ))
    resp.set_cookie('voter_id', voter_id)
    return resp


@app.route("/clear-cookie")
def clear_cookie():
    resp = make_response(redirect(url_for('hello')))
    resp.delete_cookie('voter_id')
    resp.delete_cookie('voter_name')
    resp.delete_cookie('has_voted')
    return resp


if __name__ == "__main__":
    app.run(host='0.0.0.0', port=80, debug=True, threaded=True)