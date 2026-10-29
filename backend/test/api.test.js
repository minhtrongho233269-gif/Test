import {test,beforeEach} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {newDb} from 'pg-mem';
import request from 'supertest';
import {createApp} from '../src/app.js';
import {hash} from '../src/security.js';
let app,pool,mails;
beforeEach(async()=>{
 const db=newDb(); const pg=db.adapters.createPg();pool=new pg.Pool();
 await pool.query(await readFile(new URL('../src/schema.sql',import.meta.url),'utf8'));
 mails=[];app=createApp({pool,env:{JWT_SECRET:'test-secret-with-more-than-32-characters'},sendMail:async(email,code)=>mails.push({email,code})});
});
async function register(username='parent1'){
 const r=await request(app).post('/auth/register').send({username,email:username+'@example.com',name:'Test Parent',password:'StrongPass123!'}).expect(201);
 const code=mails.at(-1).code;
 const s=await request(app).post('/auth/otp').send({challengeId:r.body.challengeId,code}).expect(200);
 return {...s.body,challenge:r.body.challengeId,code};
}
const agent=token=>({Authorization:'Bearer '+token});
test('registration verifies OTP, stores only digest and rejects replay',async()=>{
 const u=await register();assert.equal(u.user.role,'parent');assert.ok(u.token);assert.equal(u.user.password,undefined);
 await request(app).post('/auth/otp').send({challengeId:u.challenge,code:u.code}).expect(401);
 await request(app).get('/me').set(agent(u.token)).expect(200);
 await request(app).get('/me').expect(401);
});
test('password login needs email OTP; wrong attempts lock challenge',async()=>{
 await register();await request(app).post('/auth/login').send({username:'parent1',password:'wrong'}).expect(401);
 const r=await request(app).post('/auth/login').send({username:'parent1',password:'StrongPass123!'}).expect(200);
 assert.equal(r.body.token,undefined);assert.equal(r.body.code,undefined);
 const wrong=mails.at(-1).code==='000000'?'111111':'000000';
 for(let i=0;i<5;i++)await request(app).post('/auth/otp').send({challengeId:r.body.challengeId,code:wrong}).expect(401);
 await request(app).post('/auth/otp').send({challengeId:r.body.challengeId,code:mails.at(-1).code}).expect(401);
 const c=(await pool.query('SELECT * FROM challenges WHERE id=$1',[r.body.challengeId])).rows[0];assert.equal(c.digest,hash(mails.at(-1).code));assert.equal(c.attempts,5);
});
test('CRUD is isolated between families and validates limits',async()=>{
 const a=await register('family_a'),b=await register('family_b');
 const c=await request(app).post('/children').set(agent(a.token)).send({name:'An',age:9,daily_limit:90}).expect(201);
 await request(app).put('/children/'+c.body.id).set(agent(b.token)).send({name:'Hack',age:9,daily_limit:90}).expect(404);
 await request(app).post('/children').set(agent(a.token)).send({name:'An',age:99,daily_limit:0}).expect(400);
 const list=await request(app).get('/children').set(agent(b.token)).expect(200);assert.equal(list.body.length,0);
 const d=await request(app).post(`/children/${c.body.id}/devices`).set(agent(a.token)).send({name:'Phone'}).expect(201);
 await request(app).put('/devices/'+d.body.id).set(agent(a.token)).send({name:'New Phone'}).expect(200);
 await request(app).delete('/devices/'+d.body.id).set(agent(b.token)).expect(404);
 await request(app).delete('/devices/'+d.body.id).set(agent(a.token)).expect(204);
 await request(app).delete('/children/'+c.body.id).set(agent(a.token)).expect(204);
});
test('NFC binds a tag; agreements require parent approval',async()=>{
 const a=await register();const c=(await request(app).post('/children').set(agent(a.token)).send({name:'An',age:9,daily_limit:90})).body;
 const path='/children/'+c.id;await request(app).put(path+'/nfc').set(agent(a.token)).send({tagHash:hash('tag')}).expect(200);
 await request(app).post(path+'/checkins').set(agent(a.token)).send({tagHash:hash('wrong')}).expect(403);
 await request(app).post(path+'/checkins').set(agent(a.token)).send({tagHash:hash('tag')}).expect(201);
 const checks=await request(app).get(path+'/checkins').set(agent(a.token)).expect(200);assert.equal(checks.body.length,1);
 const r=await request(app).post(path+'/agreements').set(agent(a.token)).send({title:'Read books',reward:15}).expect(201);
 await request(app).patch('/agreements/'+r.body.id).set(agent(a.token)).send({status:'approved'}).expect(200);
});
test('registration cannot grant admin; staff cannot access family data',async()=>{
 const a=await register();await request(app).get('/admin/users').set(agent(a.token)).expect(403);
 await pool.query("UPDATE users SET role='staff' WHERE id=$1",[a.user.id]);
 await request(app).get('/staff/dashboard').set(agent(a.token)).expect(200);
 await request(app).post('/children').set(agent(a.token)).send({name:'An',age:9,daily_limit:90}).expect(403);
});

test('Google exchange for password account requires OTP and preserves account',async()=>{
 const u=await register();const {randomUUID}=await import('node:crypto');const verifier='v'.repeat(40),code='c'.repeat(40);
 await pool.query("INSERT INTO challenges(id,user_id,kind,digest,expires_at,payload) VALUES($1,$2,'oauth-exchange',$3,now()+interval '1 minute',$4)",[randomUUID(),u.user.id,hash(code),JSON.stringify({verifierHash:hash(verifier)})]);
 await request(app).post('/auth/google/exchange').send({code,verifier:'wrong'.repeat(8)}).expect(401);
 const r=await request(app).post('/auth/google/exchange').send({code,verifier}).expect(200);
 assert.equal(r.body.requiresOtp,true);assert.equal(r.body.token,undefined);
 const verified=await request(app).post('/auth/otp').send({challengeId:r.body.challengeId,code:mails.at(-1).code}).expect(200);
 assert.equal(verified.body.user.id,u.user.id);
 await request(app).post('/auth/google/exchange').send({code,verifier}).expect(401);
});

test('location is opt-in, isolated by family and removable by linked child',async()=>{
 const parent=await register('locparent'),child=await register('locchild'),other=await register('locother');
 await pool.query("UPDATE users SET role='child' WHERE id=$1",[child.user.id]);
 const c=(await request(app).post('/children').set(agent(parent.token)).send({name:'An',age:9,daily_limit:90}).expect(201)).body;
 await pool.query('INSERT INTO child_links(user_id,child_id) VALUES($1,$2)',[child.user.id,c.id]);
 const path='/children/'+c.id+'/location';
 const point={latitude:10.8,longitude:106.7,accuracy:15};
 await request(app).put(path).set(agent(parent.token)).send(point).expect(403);
 await request(app).put(path).set(agent(child.token)).send({...point,latitude:999}).expect(400);
 await request(app).put(path).set(agent(child.token)).send(point).expect(200);
 const r=await request(app).get(path).set(agent(parent.token)).expect(200);assert.equal(r.body.latitude,10.8);
 await request(app).get(path).set(agent(other.token)).expect(404);
 await request(app).delete(path).set(agent(other.token)).expect(403);
 await request(app).delete(path).set(agent(child.token)).expect(204);
 const empty=await request(app).get(path).set(agent(parent.token)).expect(200);assert.equal(empty.body,null);
});
