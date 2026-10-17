#!/usr/bin/env python3
"""Build Automate 1.53.2 flows using the installed app's version 114 format."""

from dataclasses import dataclass, field
from pathlib import Path
import json
import os
import struct


# Automate's built-in Flow channel preserves the user's Android alert settings.
FLOW_CHANNEL = 'da34068b-5b0a-50be-829b-b38f72ddb6a7'


@dataclass
class Raw:
    kind: str
    value: object


@dataclass(eq=False)
class Obj:
    type_id: int
    fields: dict = field(default_factory=dict)


class Writer:
    """Encode graph references before their fields so cycles remain valid."""
    def __init__(self):
        self.data = bytearray()
        self.seen = {}

    def uint(self, n):
        while n >= 128:
            self.data.append((n & 127) | 128)
            n >>= 7
        self.data.append(n)

    def sint(self, n):
        self.uint(n * 2 if n >= 0 else -n * 2 - 1)

    def raw(self, item):
        kind, value = item.kind, item.value
        if kind == 'sint':
            self.sint(value)
        elif kind == 'uint':
            self.uint(value)
        elif kind == 'byte':
            self.data.append(int(value))
        elif kind == 'double':
            self.data.extend(struct.pack('>d', value))
        elif kind == 'utf':
            data = bytearray()
            units = value.encode('utf-16-be', errors='surrogatepass')
            for i in range(0, len(units), 2):
                code = (units[i] << 8) | units[i + 1]
                if 0 < code < 128:
                    data.append(code)
                elif code < 2048:
                    data.extend((0xc0 | code >> 6, 0x80 | code & 63))
                else:
                    data.extend((0xe0 | code >> 12, 0x80 | code >> 6 & 63, 0x80 | code & 63))
            self.uint(len(data))
            self.data.extend(data)
        else:
            raise ValueError(kind)

    def obj(self, value):
        if isinstance(value, Raw):
            self.raw(value)
            return
        if value is None:
            self.sint(0)
            return
        key = ('variable', value.fields['name'].value) if value.type_id == 102 else id(value)
        if key in self.seen:
            self.sint(-self.seen[key] - 1)
            return
        self.seen[key] = len(self.seen)
        self.sint(value.type_id)
        for item in value.fields.values():
            self.obj(item)

    def flow(self, blocks):
        self.data.extend(struct.pack('>IH', 0x4c41466c, 114))
        self.sint(len(blocks) + 1)
        self.uint(len(blocks))
        for block in blocks:
            self.obj(block)
        return bytes(self.data)


def val(value):
    if isinstance(value, Obj):
        return value
    if value is None:
        return Obj(103)
    if isinstance(value, str):
        return Obj(106, {'value': Raw('utf', value)})
    return Obj(104, {'value': Raw('double', float(value))})


def integer(n):
    return Obj(16, {"value": Raw("sint", n)})


def var(name):
    return Obj(102, {'name': Raw('utf', name)})


def block(blocks, type_id, *, x=0, y=None, **fields):
    n = len(blocks) + 1
    item = Obj(type_id, {'id': Raw('sint', n), 'x': Raw('sint', x),
                        'y': Raw('sint', (n - 1) * 6 if y is None else y), **fields})
    blocks.append(item)
    return item


def begin(blocks):
    return block(blocks, 1072, next=None, title=Raw('utf', ''), hidden=Raw('byte', 0),
                 parallel=Raw('byte', 0), payload=None, fiber=None)


def fork(blocks, **position):
    return block(blocks, 1060, **position, next=None, child=None, stop=Raw('byte', 1),
                 child_uri=None, parent_uri=var('alarmFiber'))


def accept(blocks, port, path, method='GET', **position):
    return block(blocks, 1415, **position, next=None, alias=None, method=val(method),
                 uri=val(path), content_type=None, save_body=None, body_path=None,
                 request_uri=None, request_body=None, request_headers=None,
                 interface=val(1), port=val(port))


def response(blocks, body, **position):
    return block(blocks, 1416, **position, next=None, status=val(200),
                 content_type=val('text/plain'), body=val(body), body_path=None, headers=None)


def notify(blocks, title, message):
    return block(blocks, 1103, yes=None, no=None, continuity=integer(1), title=val(title),
                 message=val(message), short=None, picture=None, person=None, small_icon=None,
                 large_icon=None, layout=None, big_layout=None, heads_up=None, color=None,
                 cancellable=val(1), ongoing=val(0), visibility=None, category=None,
                 group=None, channel=None, progress=None, when=None, key=None, interface_uri=None)



def expr(kind, *args):
    return Obj(kind, {str(i): val(a) for i, a in enumerate(args)})


def many(kind, *args):
    return Obj(kind, {'count': Raw('uint', len(args)), **{str(i): val(a) for i, a in enumerate(args)}})


def dictionary(items):
    fields = {'count': Raw('uint', len(items))}
    for i, (k, v) in enumerate(items):
        fields.update({f'k{i}': val(k), f'v{i}': val(v), f't{i}': Raw('sint', -1)})
    return Obj(133, fields)


def sub(a, b): return expr(137, a, b)
def eq(a, b): return expr(122, a, b)
def choose(c, a, b): return expr(120, c, a, b)
def AND(*xs):
    result = xs[0]
    for x in xs[1:]: result = expr(111, result, x)
    return result

def OR(a,b): return expr(136,a,b)
def cat(a,b): return expr(119,a,b)
def length(a): return expr(126,a)
def now(): return Obj(202)
def runtime(): return expr(402,'fiberUri')


def complete(config):
    blocks=[]
    def action(kind, **fields): return block(blocks, kind, next=None, **fields)
    def decision(condition): return block(blocks,1058,yes=None,no=None,condition=val(condition))
    def wifi(mode):
        return block(blocks,1146,yes=None,no=None,continuity=integer(mode),ssid=val(config['ssid']),bssid=None,connected_ssid=None,connected_bssid=None,capabilities=None,link_speed=None,frequency=None,ip=None)
    def json_response(body):
        r=response(blocks,expr(316,body));r.fields['content_type']=val('application/json');return r
    def connect(a,b): a.fields['next']=b
    req=var('request');op=sub(req,'op');key=sub(req,'key');fired=sub(req,'firedAt')
    journal=var('journal');records=sub(journal,'records');record=sub(records,key)
    deadline=expr(110,fired,config.get('ringSeconds',600));oldest=sub(records,sub(expr(343,records),0))
    floor=sub(journal,'floor')
    start=begin(blocks)
    check=wifi(0);wait=wifi(1);listener_fork=fork(blocks)
    listener_fork.fields.update(child_uri=var('listenerFiber'),parent_uri=None)
    departure=wifi(1);stop_listener=action(1061,fiber=var('listenerFiber'))
    load=action(1256,atomic=journal)
    catch=action(1263,failure=None,retry_limit=None,retry_count=None,failure_statement=None,failure_type=None,failure_message=None)
    accept_req=accept(blocks,config.get('port',8080),'/qs-alarm','POST')
    accept_req.fields.update(save_body=val(1),request_body=var('body'))
    decode=action(1012,value=expr(315,var('body')),variable=req)
    probe=AND(eq(op,'probe'),expr(322,sub(req,'nonce'),'[a-f0-9]{64}'))
    command=AND(eq(sub(req,'secret'),config['secret']),expr(322,op,'ring|stop|state'),expr(322,key,'[A-Za-z0-9_.:-]{1,128}'),eq(expr(356,fired),'number'),expr(123,fired,0),expr(127,fired,expr(110,now(),30)))
    auth=decision(command)
    probe_reply=json_response(choose(probe,dictionary([('v',1),('pairId',config['pairId']),('nonce',sub(req,'nonce')),('proof',expr(393,cat(config['secret']+':',sub(req,'nonce')),None))]),dictionary([('error','invalid request')])))
    probe_reply.fields['status']=choose(probe,200,400)
    is_ring=decision(eq(op,'ring'))
    fresh=decision(AND(eq(record,None),expr(124,deadline,now()),OR(eq(floor,None),expr(124,fired,floor)),OR(expr(128,length(records),128),expr(127,sub(oldest,'deadline'),now()))))
    alarm_fork=fork(blocks)
    alarm_fork.fields.update(child_uri=var('alarmFiber'),parent_uri=None)
    # Only the dispatcher mutates this journal; workers are represented by their fiber URI.
    new_record=dictionary([('fiber',choose(eq(op,'ring'),var('alarmFiber'),sub(record,'fiber'))),('owner',choose(eq(op,'ring'),runtime(),sub(record,'owner'))),('deadline',choose(eq(op,'ring'),deadline,sub(record,'deadline'))),('firedAt',choose(eq(op,'ring'),fired,sub(record,'firedAt'))),('stopped',choose(eq(op,'stop'),1,0))])
    trimmed=choose(AND(expr(123,length(records),128),eq(record,None)),expr(331,records,expr(383,expr(343,records),-127,None)),records)
    new_floor=choose(AND(expr(123,length(records),128),eq(record,None)),choose(expr(124,sub(oldest,'firedAt'),floor),sub(oldest,'firedAt'),floor),floor)
    update=action(1012,value=dictionary([('records',many(369,trimmed,dictionary([(key,new_record)]))),('floor',new_floor)]),variable=journal)
    store=action(1257,atomic=journal)
    stopped=block(blocks,1195,yes=None,no=None,continuity=integer(0),fiber=sub(record,'fiber'))
    status=choose(eq(record,None),'unknown',choose(sub(record,'stopped'),'stopped',choose(expr(135,sub(record,'owner'),runtime()),'away',choose(expr(127,sub(record,'deadline'),now()),'timed_out','dismissed'))))
    def state_body(state): return dictionary([('v',1),('pairId',config['pairId']),('key',key),('firedAt',fired),('state',state)])
    active=json_response(state_body('ringing'))
    inactive=json_response(state_body(status))
    is_stop=decision(eq(op,'stop'))
    stop_alarm=action(1061,fiber=sub(record,'fiber'))
    ringtone=action(1044,ringtone_type=val(4),uri=var('soundUri'))
    play=action(1124,continuity=integer(0),stream=val(4),volume=val(config.get('volume',100)),focus=None,notification_channel=None,uri=var('soundUri'),repeat=val(1),position=None,speed=None,pitch=None)
    timeout_fork=fork(blocks)
    timeout_fork.fields.update(child_uri=None,parent_uri=var('ownerFiber'))
    delay=action(1046,continuity=integer(0),wakeup=val(1),duration=expr(138,deadline,now()))
    stop_owner=action(1061,fiber=var('ownerFiber'))
    notification=notify(blocks,'Desktop Alarm',sub(req,'title'))
    notification.fields.update(category=val('alarm'),message=sub(req,'title'),
                               channel=val(FLOW_CHANNEL))
    settle=action(1046,continuity=integer(0),wakeup=val(1),duration=val(3))
    connect(start,check);check.fields.update(yes=listener_fork,no=wait);wait.fields.update(yes=listener_fork,no=wait)
    listener_fork.fields.update(next=departure,child=load);departure.fields.update(yes=departure,no=stop_listener);connect(stop_listener,check)
    connect(load,settle);connect(settle,catch);connect(catch,accept_req);catch.fields['failure']=accept_req
    connect(accept_req,decode);connect(decode,auth);auth.fields.update(yes=is_ring,no=probe_reply);connect(probe_reply,accept_req)
    is_ring.fields.update(yes=fresh,no=is_stop);fresh.fields.update(yes=alarm_fork,no=stopped)
    alarm_fork.fields.update(next=update,child=ringtone);connect(update,store);connect(store,stopped)
    stopped.fields.update(yes=inactive,no=active);connect(active,accept_req);connect(inactive,accept_req)
    is_stop.fields.update(yes=stop_alarm,no=stopped);connect(stop_alarm,update)
    connect(ringtone,play);connect(play,timeout_fork);timeout_fork.fields.update(next=notification,child=delay);connect(delay,stop_owner)
    # Ending the sound-owning fiber releases both playback and its notification.
    # Keep the watcher, dispatcher and sound workers in separate editor columns.
    for i, item in enumerate([start, check, wait, listener_fork, departure, stop_listener]):
        item.fields.update(x=Raw('sint', 0), y=Raw('sint', i * 6))
    for i, item in enumerate([load, settle, catch, accept_req, decode, auth, is_ring, fresh,
                              alarm_fork, update, store, stopped, active]):
        item.fields.update(x=Raw('sint', 12), y=Raw('sint', i * 6))
    for item, x, y in [(probe_reply,24,30), (is_stop,24,36), (stop_alarm,24,42),
                       (inactive,24,72), (ringtone,36,48), (play,36,54),
                       (timeout_fork,36,60), (notification,36,66), (delay,48,66), (stop_owner,48,72)]:
        item.fields.update(x=Raw('sint', x), y=Raw('sint', y))
    return blocks

if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser();p.add_argument('config',type=Path);p.add_argument('output',type=Path);args=p.parse_args()
    cfg=json.loads(args.config.read_text())
    cfg['ssid'] = cfg.get('ssid') or cfg['homeNetworks'][0]['ssid']
    if len(cfg.get('homeNetworks', [None])) != 1:
        p.error('This 29-block flow supports one home Wi-Fi network')
    cfg['ringSeconds'] = 600
    cfg.setdefault('volume', 100)
    blocks=complete(cfg)
    descriptor = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, 'wb') as output:
        os.fchmod(output.fileno(), 0o600)
        output.write(Writer().flow(blocks))
    print(f'{len(blocks)} blocks; generated {args.output.name}')
