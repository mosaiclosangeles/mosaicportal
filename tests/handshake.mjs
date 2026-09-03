import {chromium} from '/opt/node22/lib/node_modules/playwright/index.mjs';
const b=await chromium.launch();let bad=0;
const step=async(n,f)=>{try{await f();console.log('  ok  '+n);}catch(e){console.log('  FAIL '+n+' — '+e.message);bad++;}};
const p=await b.newPage({viewport:{width:1400,height:900},deviceScaleFactor:2});
const errs=[];p.on('pageerror',e=>errs.push(e.message));
await p.route('**/*',r=>{
  const u=r.request().url();
  if(u.startsWith('http://127.0.0.1:8100')||u.startsWith('http://127.0.0.1:8099'))return r.continue();
  return r.abort();
});
// the portal, with the facilities frame pointed at the OTHER origin
await p.goto('http://127.0.0.1:8100/facilities',{waitUntil:'domcontentloaded',timeout:25000});
await p.waitForFunction(()=>document.querySelectorAll('#nav button[data-go]').length>3,{timeout:12000});
await p.evaluate(()=>{
  const f=document.querySelector('.embed-wrap iframe');
  f.src='http://127.0.0.1:8099/harness-frame.html?embed=portal';
});
console.log('--- the portal hands the session to the frame ---');
await step('the frame gets in without ever reading a cookie',async()=>{
  const fr=await (async()=>{for(let i=0;i<25;i++){
    const f=p.frames().find(x=>x.url().includes('harness-frame'));
    if(f){try{if(await f.evaluate(()=>!!document.getElementById('gate')))return f;}catch(_){}}
    await p.waitForTimeout(500);} return null;})();
  if(!fr)throw new Error('the frame never attached');
  await fr.waitForFunction(()=>document.getElementById('gate').classList.contains('hide'),{timeout:20000});
  const n=await fr.evaluate(()=>window.__handshake||0);
  console.log('       setSession calls from the handshake: '+n);
  if(!n)throw new Error('it got in some other way, not the handshake');
});
await step('the app really rendered inside the frame',async()=>{
  const fr=p.frames().find(x=>x.url().includes('harness-frame'));
  const t=await fr.evaluate(()=>document.getElementById('main').textContent);
  if(!/Every request across Mosaic/.test(t))throw new Error('no requests page: '+t.slice(0,60));
  const rail=await fr.evaluate(()=>getComputedStyle(document.querySelector('.rail')).display);
  if(rail!=='none')throw new Error('the rail should stay hidden in the frame');
});
await step('no password box was shown at any point',async()=>{
  const fr=p.frames().find(x=>x.url().includes('harness-frame'));
  const html=await fr.evaluate(()=>document.getElementById('gate').innerHTML);
  if(/type="password"/.test(html))throw new Error('a password box rendered');
});
console.log('--- a page that is not the portal gets nothing ---');
await step('an untrusted origin asking for the token is ignored',async()=>{
  const got=await p.evaluate(()=>new Promise(res=>{
    // the portal's listener must reject anything that is not *.mosaic.org or
    // this harness's own localhost origin
    const results=[];
    const orig=window.addEventListener;
    // ask as if we were an evil origin by calling the handler's guard directly
    results.push(EMBED_TRUSTED('https://evil.example.com'));
    results.push(EMBED_TRUSTED('https://portal.mosaic.org.evil.com'));
    results.push(EMBED_TRUSTED('http://mosaic.org'));
    results.push(EMBED_TRUSTED('https://facilities.mosaic.org'));
    res(results);
  }));
  console.log('       evil.example.com:'+got[0]+'  lookalike:'+got[1]+'  http:'+got[2]+'  facilities:'+got[3]);
  if(got[0]||got[1]||got[2])throw new Error('an untrusted origin was accepted');
  if(!got[3])throw new Error('the real facilities origin was rejected');
});
if(errs.length)console.log('\nJS errors:\n  '+errs.join('\n  '));
await p.screenshot({path:'handshake.png'});
console.log(bad||errs.length?'\nFAILED':'\nall good');
await b.close();process.exitCode=(bad||errs.length)?1:0;
