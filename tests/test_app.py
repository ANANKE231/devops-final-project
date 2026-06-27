import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'app'))

import pytest
from app import app as flask_app


@pytest.fixture
def client():
    flask_app.config['TESTING'] = True
    with flask_app.test_client() as c:
        yield c


def test_health_returns_ok(client):
    res = client.get('/health')
    assert res.status_code == 200
    data = res.get_json()
    assert data['status'] == 'ok'
    assert 'timestamp' in data
    assert 'version' in data


def test_health_has_env(client):
    res = client.get('/health')
    data = res.get_json()
    assert 'env' in data


def test_index_loads(client):
    res = client.get('/')
    assert res.status_code == 200
    assert b'DevOps Demo App' in res.data


def test_post_message_success(client):
    res = client.post('/api/messages', json={"author": "Alice", "body": "Hello world"})
    assert res.status_code == 201
    data = res.get_json()
    assert data['status'] == 'created'
    assert data['message']['author'] == 'Alice'
    assert data['message']['body'] == 'Hello world'


def test_post_message_missing_body(client):
    res = client.post('/api/messages', json={"author": "Alice"})
    assert res.status_code == 400
    data = res.get_json()
    assert 'error' in data


def test_get_messages(client):
    client.post('/api/messages', json={"author": "Bob", "body": "Test message"})
    res = client.get('/api/messages')
    assert res.status_code == 200
    data = res.get_json()
    assert 'messages' in data
    assert isinstance(data['messages'], list)


def test_dynamic_echo_route(client):
    res = client.get('/api/echo/devops')
    assert res.status_code == 200
    data = res.get_json()
    assert data['echo'] == 'devops'
    assert 'timestamp' in data


def test_echo_different_values(client):
    for name in ['alice', 'bob', 'test123']:
        res = client.get(f'/api/echo/{name}')
        assert res.status_code == 200
        assert res.get_json()['echo'] == name
