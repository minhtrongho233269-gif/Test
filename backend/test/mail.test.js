import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createMailer} from '../src/mail.js';
test('HTTPS mail payload and authorization',async()=>{
 let request;
 const send=createMailer({RESEND_API_KEY:'secret',MAIL_FROM:'otp@example.com'},async(url,options)=>{request={url,...options};return {ok:true};});
 await send('user@example.com','123456','verify');
 assert.equal(request.url,'https://api.resend.com/emails');
 assert.equal(request.headers.Authorization,'Bearer secret');
 assert.deepEqual(JSON.parse(request.body).to,['user@example.com']);
 assert.match(JSON.parse(request.body).text,/123456/);
});
test('provider failures do not leak key or OTP',async()=>{
 const send=createMailer({RESEND_API_KEY:'secret',MAIL_FROM:'otp@example.com'},async()=>({ok:false}));
 await assert.rejects(send('user@example.com','123456','login'),e=>e.status===503&&!e.message.includes('123456')&&!e.message.includes('secret'));
});
test('missing credentials fail closed',async()=>{await assert.rejects(createMailer({})('a@b.com','123456','login'),e=>e.status===503);});
