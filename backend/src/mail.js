import nodemailer from 'nodemailer';
export function createMailer(env=process.env, fetchImpl=fetch) {
 const provider=env.MAIL_PROVIDER || 'resend';
 if(provider==='smtp') {
  const transport=nodemailer.createTransport({host:env.SMTP_HOST,port:Number(env.SMTP_PORT||587),secure:env.SMTP_PORT==='465',auth:{user:env.SMTP_USER,pass:env.SMTP_PASSWORD},connectionTimeout:15000});
  return (email,code,kind)=>transport.sendMail(message(env.SMTP_FROM,email,code,kind));
 }
 if(provider!=='resend') throw new Error('MAIL_PROVIDER không hợp lệ');
 return async(email,code,kind)=>{
  if(!env.RESEND_API_KEY||!env.MAIL_FROM)throw Object.assign(new Error('Dịch vụ email chưa được cấu hình'),{status:503});
  try {
   const response=await fetchImpl('https://api.resend.com/emails',{method:'POST',headers:{Authorization:`Bearer ${env.RESEND_API_KEY}`,'Content-Type':'application/json'},body:JSON.stringify(message(env.MAIL_FROM,email,code,kind)),signal:AbortSignal.timeout(15000)});
   if(!response.ok)throw new Error('Email provider rejected request');
   return {accepted:true};
  }catch {throw Object.assign(new Error('Chưa gửi được OTP. Vui lòng thử lại sau hoặc liên hệ quản trị.'),{status:503});}
 };
}
function message(from,email,code,kind){return {from,to:[email],subject:'ChildGuard • Mã xác thực',text:`Mã ${kind==='verify'?'xác minh tài khoản':'đăng nhập'} ChildGuard của bạn: ${code}. Có hiệu lực 5 phút. Không chia sẻ mã này.`};}
