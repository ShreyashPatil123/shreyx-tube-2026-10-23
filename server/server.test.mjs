import { test } from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import net from 'node:net';
import { createGateway, validateRequest, validateOutput } from './server.mjs';

const token = 'synthetic-user-access-token-123456789';
const request = { videoId:'abcdefghijk', title:'Learning', task:'summary', question:'',
  segments:[{ id:0, text:'Active recall means retrieving information from memory.', startMs:12000 }] };
const output = { summary:'Recall involves retrieval.', detailed:'The transcript describes retrieving information from memory.', answer:'',
  takeaways:['Recall information.'], concepts:['Recall'], notCovered:false,
  evidence:[{ segmentId:0, quote:request.segments[0].text }], sections:[{ segmentId:0, heading:'Recall' }] };
const provider = (value = output) => new Response(JSON.stringify({ candidates:[{ finishReason:'STOP', content:{ parts:[{ text:JSON.stringify(value) }] } }] }));
async function gateway(t, options = {}) {
  const app = createGateway({ apiKey:'synthetic-provider-key', accessTokens:[token], fetchFn:async () => provider(), ...options });
  app.listen(0,'127.0.0.1'); await once(app,'listening');
  t.after(() => { app.closeAllConnections(); return new Promise((resolve) => app.close(resolve)); });
  const url = `http://127.0.0.1:${app.address().port}`;
  return { url, send:(data = request, headers = {}) => fetch(url+'/v1/analyze', { method:'POST',
    headers:{ 'content-type':'application/json', authorization:'Bearer '+token, ...headers }, body:JSON.stringify(data) }) };
}
test('healthy process is not reported AI-ready without server credentials', async (t) => {
  const g = await gateway(t,{apiKey:''});
  assert.equal((await fetch(g.url+'/health')).status,200);
  assert.equal((await fetch(g.url+'/ready')).status,503);
  assert.equal((await g.send()).status,503);
});
test('stalled authenticated uploads are terminated without calling Gemini', {timeout:2000}, async (t) => {
  let calls=0;
  const g=await gateway(t,{providerTimeoutMs:80, fetchFn:async()=>{calls++;return provider();}});
  const address=new URL(g.url);
  const socket=net.createConnection({host:address.hostname,port:Number(address.port)});
  await once(socket,'connect');
  socket.on('error',()=>{});
  socket.write(`POST /v1/analyze HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nAuthorization: Bearer ${token}\r\nContent-Length: 500\r\n\r\n{"videoId":`);
  await once(socket,'close');
  assert.equal(calls,0);
});
test('authorized summary calls only the fixed Gemini origin and returns validated evidence', async (t) => {
  let captured;
  const g = await gateway(t,{fetchFn:async (url, options) => { captured={url,options}; return provider(); }});
  const response = await g.send({...request, url:'http://169.254.169.254/metadata', cookies:'must-not-forward'});
  assert.equal(response.status,200);
  const result = await response.json();
  assert.deepEqual(result.evidence,output.evidence);
  assert.equal(captured.url,'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent');
  assert.equal(captured.options.redirect,'error');
  assert.equal(captured.options.headers['x-goog-api-key'],'synthetic-provider-key');
  assert.equal(captured.options.headers.cookie,undefined);
  assert(!captured.options.body.includes('169.254.169.254'));
  assert(!captured.options.body.includes('must-not-forward'));
  const body=JSON.parse(captured.options.body);
  assert.equal(body.generationConfig.maxOutputTokens,3072);
  assert.equal(body.tools,undefined);
  assert(body.systemInstruction.parts[0].text.includes('untrusted'));
  assert.equal(response.headers.get('cache-control'),'no-store');
});
test('missing and incorrect authentication cannot call the provider', async (t) => {
  let calls=0;
  const g=await gateway(t,{fetchFn:async()=>{ calls++;return provider(); }});
  for(const authorization of ['', 'Bearer wrong']) assert.equal((await g.send(request,{authorization})).status,401);
  assert.equal(calls,0);
});
test('browser-origin requests and wrong content types are rejected', async (t) => {
  const g=await gateway(t);
  assert.equal((await g.send(request,{origin:'https://attacker.example'})).status,403);
  assert.equal((await g.send(request,{'content-type':'text/plain'})).status,415);
});
test('invalid, unavailable, empty and oversized source inputs fail before model use', async (t) => {
  let calls=0;const g=await gateway(t,{fetchFn:async()=>{calls++;return provider();}});
  const invalid=[null,{}, {...request,videoId:'file:///etc/passwd'}, {...request,segments:[]},
    {...request,segments:[{id:0,text:'short'}]}, {...request,segments:[{id:0,text:'x'.repeat(50001)}]},
    {...request,question:'x'.repeat(1001)}, {...request,task:'ask'},
    {...request,segments:[{id:0,text:request.segments[0].text,startMs:-1}]}];
  for(const data of invalid) assert.equal((await g.send(data)).status,400);
  assert.equal(calls,0);
});
test('request byte limit rejects a large payload', async (t) => {
  const g=await gateway(t);
  assert.equal((await g.send({...request,extra:'x'.repeat(256001)})).status,413);
});
test('malformed JSON is a useful client error',async(t)=>{
  const g=await gateway(t);
  const r=await fetch(g.url+'/v1/analyze',{method:'POST',headers:{authorization:'Bearer '+token,'content-type':'application/json'},body:'{' });
  assert.equal(r.status,400);
});
test('per-user rate limits and global budget do not silently retry AI calls', async(t)=>{
  let calls=0;const g=await gateway(t,{perMinute:1,fetchFn:async()=>{calls++;return provider();}});
  assert.equal((await g.send()).status,200);
  const limited=await g.send();assert.equal(limited.status,429);assert.equal(limited.headers.get('retry-after'),'60');
  assert.equal(calls,1);
  const daily=await gateway(t,{dailyLimit:1});
  assert.equal((await daily.send()).status,200);assert.equal((await daily.send()).status,429);
});
test('provider quota and unavailable responses have safe error bodies',async(t)=>{
  for(const status of [429,403,503]) {
    const g=await gateway(t,{fetchFn:async()=>new Response('synthetic-provider-key SECRET_DETAIL',{status})});
    const r=await g.send();assert.equal(r.status,status===429?429:503);
    const body=await r.text();assert(!body.includes('SECRET_DETAIL'));assert(!body.includes('synthetic-provider-key'));
  }
});
test('invalid JSON, blocked output and invented quotes fail visibly',async(t)=>{
  const responses=[new Response('{'),new Response(JSON.stringify({candidates:[{finishReason:'MAX_TOKENS'}]})),
    provider({...output,evidence:[{segmentId:0,quote:'This quotation does not exist in the source.'}]}),
    provider({...output,evidence:[{segmentId:44,quote:request.segments[0].text}]})];
  for(const response of responses) {
    const g=await gateway(t,{fetchFn:async()=>response});assert.equal((await g.send()).status,502);
  }
});
test('unsupported questions get a fixed explanation, never an unsupported model answer',()=>{
  const value=validateOutput({...output,notCovered:true,answer:'invented answer',evidence:[]},request);
  assert.equal(value.answer,'The provided transcript does not cover this question.');
  assert.equal(value.summary,'');assert.deepEqual(value.sections,[]);
});
test('timestamp output is derived from IDs, not accepted from the model',()=>{
  const value=validateOutput({...output,sections:[{segmentId:0,heading:'Recall',startMs:999999}]},request);
  assert.deepEqual(value.sections,[{segmentId:0,heading:'Recall'}]);
  assert.equal(validateRequest(request).segments[0].startMs,12000);
});
test('cancelled provider request times out without a leaked exception', async(t)=>{
  const g=await gateway(t,{providerTimeoutMs:30,fetchFn:async(_url,{signal})=>new Promise((_resolve,reject)=>{
    if(signal.aborted)reject(new Error('aborted'));else signal.addEventListener('abort',()=>reject(new Error('aborted')),{once:true});
  })});
  assert.equal((await g.send()).status,504);
});
test('concurrency limit rejects extra work while a model call is active',async(t)=>{
  let finish;let started;
  const ready=new Promise((resolve)=>{started=resolve;});
  const g=await gateway(t,{concurrency:1,fetchFn:async()=>{started();return new Promise((resolve)=>{finish=()=>resolve(provider());});}});
  const first=g.send();await ready;
  assert.equal((await g.send()).status,503);finish();assert.equal((await first).status,200);
});
test('model name and access-token configuration cannot change the outbound origin',()=>{
  assert.throws(()=>createGateway({model:'../attack'}));
  assert.throws(()=>createGateway({accessTokens:['short']}));
});
