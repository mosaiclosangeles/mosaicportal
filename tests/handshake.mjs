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
  const f=document.querySelector('#embedHost iframe:not([hidden])');
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
/* --- "Book the space": a framed app asking the portal to move ---
   The planning board cannot file a facility request itself, so it asks the
   portal to open Facilities on the new-request form with the event in it. The
   portal is the middle of that chain and the only part of it that had nothing
   driving it. The message is posted from the facilities frame here because it
   is a genuine second origin; the board sends the same shape, and its own suite
   (features.mjs, "the hand-off carries the event…") asserts the keys. */
console.log('--- a framed app asking the portal to open Facilities ---');
/* Posted from inside the frame, by the frame, on its own origin — the parent
   cannot reach across into it, and a message the parent posts to itself would
   not be testing the origin check at all. */
/* Handling the message re-renders, which puts the frame back on the real
   facilities.mosaic.org src — right for production, and it means the harness
   has to be pointed at the second origin again before each message. */
const repoint=async()=>{
  await p.evaluate(()=>{
    const f=document.querySelector('#embedHost iframe:not([hidden])');
    if(f&&!f.src.includes('harness-frame'))f.src='http://127.0.0.1:8099/harness-frame.html?embed=portal';
  });
  for(let i=0;i<25;i++){
    if(p.frames().some(x=>x.url().includes('harness-frame')))return;
    await p.waitForTimeout(300);
  }
  throw new Error('the facilities frame never came back');
};
const navigate=async(msg)=>{
  await repoint();
  const fr=p.frames().find(x=>x.url().includes('harness-frame'));
  if(!fr)throw new Error('the facilities frame is gone');
  await fr.evaluate(m=>parent.postMessage(m,'*'),msg);
  await p.waitForTimeout(500);
  return p.evaluate(()=>({section:S.section,facPath:S.facPath,
    book:(S.navBook&&S.navBook.facilities&&S.navBook.facilities.params)||null,
    src:(document.querySelector('#embedHost iframe:not([hidden])')||{}).src||''}));
};
const BOOK={type:'mosaic-navigate',section:'facilities',page:'new',params:{
  board_item:'n:2026-12-24:LA:christmas-eve',title:'Christmas Eve Service',
  date:'2026-12-24',start:'17:00',end:'19:00',campus:'LA',purpose:'Two services'}};
await step('it lands on the Facilities new-request form, in the portal',async()=>{
  const r=await navigate(BOOK);
  if(r.section!=='facilities')throw new Error('section is '+r.section);
  if(r.facPath!=='new')throw new Error('page is '+r.facPath);
});
await step('the event\'s details reach the frame\'s URL',async()=>{
  const r=await navigate(BOOK);
  for(const [k,v] of Object.entries(BOOK.params))
    if(!r.src.includes(encodeURIComponent(k)+'='+encodeURIComponent(v)))
      throw new Error(k+' did not reach the src: '+r.src.slice(0,200));
});
await step('a field nobody allowed is dropped, not passed through',async()=>{
  // An allowlist rather than a pass-through: this arrives from a framed page,
  // and whatever it can put in the URL it could put anything in.
  const r=await navigate({...BOOK,params:{...BOOK.params,role:'admin',apikey:'x'}});
  if(r.src.includes('role=')||r.src.includes('apikey='))
    throw new Error('an unlisted param was forwarded: '+r.src.slice(0,200));
  if(!('board_item' in (r.book||{})))throw new Error('the allowed ones were dropped too');
});
await step('a section that is not offered is ignored',async()=>{
  const before=await p.evaluate(()=>S.section);
  const r=await navigate({...BOOK,section:'nonsense'});
  if(r.section!==before)throw new Error('moved to '+r.section);
});
await step('clicking Facilities by hand clears the board prefill',async()=>{
  await navigate(BOOK);
  await p.click('#nav button[data-go="facilities"]');
  await p.waitForTimeout(400);
  const r=await p.evaluate(()=>({book:S.navBook&&S.navBook.facilities,
    src:(document.querySelector('#embedHost iframe:not([hidden])')||{}).src||''}));
  if(r.book)throw new Error('the prefill survived a click');
  if(r.src.includes('board_item'))throw new Error('a stale event is still in the src');
});
/* --- the portal answering for the apps that need a sign-in ---
   The board asks what is booked and what was counted for an event. It cannot
   read either itself: both live behind RLS keyed to auth.uid() and the board
   has no session. What matters here is that the answer comes back addressed to
   the item that was asked about — an answer landing on the wrong id would put
   one event's rooms on another event's card. */
console.log('--- the portal answering what a card asks ---');
await step('a request for one event is answered for that event',async()=>{
  await repoint();
  const fr=p.frames().find(x=>x.url().includes('harness-frame'));
  const got=await fr.evaluate(()=>new Promise(res=>{
    const on=e=>{const d=e.data||{};
      if(d.type==='mosaic-connected'){window.removeEventListener('message',on);res(d);}};
    window.addEventListener('message',on);
    parent.postMessage({type:'mosaic-connected-request',
      item:{id:'n:2026-12-24:LA:christmas-eve',title:'Christmas Eve',date:'2026-12-24',campus:'LA'}},'*');
    setTimeout(()=>res(null),6000);
  }));
  if(!got)throw new Error('no answer came back');
  if(got.item_id!=='n:2026-12-24:LA:christmas-eve')throw new Error('answered about '+got.item_id);
  if(!Array.isArray(got.facilities)||!Array.isArray(got.metrics))
    throw new Error('the answer is not the shape the board reads: '+JSON.stringify(got).slice(0,120));
});
await step('a request with no item id is not answered at all',async()=>{
  await repoint();
  const fr=p.frames().find(x=>x.url().includes('harness-frame'));
  const got=await fr.evaluate(()=>new Promise(res=>{
    const on=e=>{if((e.data||{}).type==='mosaic-connected'){window.removeEventListener('message',on);res('answered');}};
    window.addEventListener('message',on);
    parent.postMessage({type:'mosaic-connected-request',item:{}},'*');
    setTimeout(()=>res('quiet'),2500);
  }));
  if(got!=='quiet')throw new Error('it answered a request naming nothing');
});

/* --- the New menu on Home --- */
console.log('--- starting something from Home ---');
await step('New offers only what this person can actually reach',async()=>{
  await p.click('#nav button[data-go="home"]'); await p.waitForTimeout(400);
  await p.click('[data-newmenu]'); await p.waitForTimeout(300);
  const rows=await p.evaluate(()=>[...document.querySelectorAll('#newMenu .nm-row')].map(b=>b.dataset.newthing));
  if(!rows.length)throw new Error('the menu is empty');
  const allowed=await p.evaluate(()=>allowedSections());
  const outside=rows.filter(r=>!allowed.includes(r));
  if(outside.length)throw new Error('offers a section this person cannot see: '+outside.join(','));
});
await step('picking one lands on that app\'s own form',async()=>{
  await p.click('#newMenu [data-newthing="facilities"]'); await p.waitForTimeout(500);
  const r=await p.evaluate(()=>({section:S.section,open:S.newMenu,
    src:(document.querySelector('#embedHost iframe:not([hidden])')||{}).src||''}));
  if(r.section!=='facilities')throw new Error('landed on '+r.section);
  if(!/page=new/.test(r.src))throw new Error('not the new-request form: '+r.src.slice(0,120));
  if(r.open)throw new Error('the menu stayed open over the page');
});
await step('started from Home it carries no event, because there is none',async()=>{
  const src=await p.evaluate(()=>(document.querySelector('#embedHost iframe:not([hidden])')||{}).src||'');
  if(src.includes('board_item'))throw new Error('an event came from nowhere: '+src.slice(0,140));
});
await step('clicking away closes it',async()=>{
  await p.click('#nav button[data-go="home"]'); await p.waitForTimeout(400);
  await p.click('[data-newmenu]'); await p.waitForTimeout(250);
  await p.click('.page-head .sub'); await p.waitForTimeout(300);
  if(await p.evaluate(()=>S.newMenu))throw new Error('still open');
});
if(errs.length)console.log('\nJS errors:\n  '+errs.join('\n  '));
await p.screenshot({path:'handshake.png'});
console.log(bad||errs.length?'\nFAILED':'\nall good');
await b.close();process.exitCode=(bad||errs.length)?1:0;
