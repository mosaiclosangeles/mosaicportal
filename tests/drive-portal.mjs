import {chromium} from '/opt/node22/lib/node_modules/playwright/index.mjs';
const b=await chromium.launch();
let bad=0; const errs=[];
const step=async(n,f)=>{try{await f();console.log('  ok  '+n);}catch(e){console.log('  FAIL '+n+' — '+e.message);bad++;}};
const open=async(path)=>{
  const p=await b.newPage({viewport:{width:1500,height:1000},deviceScaleFactor:2});
  p.on('pageerror',e=>errs.push('PAGEERROR: '+e.message));
  p.on('console',m=>{if(m.type()==='error'&&!/Failed to load resource/.test(m.text()))errs.push('CONSOLE: '+m.text());});
  await p.route('**/*',r=>{
    const u=r.request().url();
    if(u.startsWith('http://127.0.0.1:8100'))return r.continue();
    // the embedded app is a real cross-origin page; stand in for it so the
    // iframe resolves without leaving the harness
    if(u.includes('facilities.mosaic.org'))
      return r.fulfill({status:200,contentType:'text/html',body:'<h1>facilities stub</h1>'});
    return r.abort();
  });
  await p.goto('http://127.0.0.1:8100'+path,{waitUntil:'domcontentloaded',timeout:25000});
  // The rail rendering is the signal that boot finished. Waiting on #main's
  // length instead misses the embed pages, whose markup is one iframe.
  // A thrown predicate aborts waitForFunction rather than retrying, so guard it.
  await p.waitForFunction(()=>document.querySelectorAll('#nav button[data-go]').length>3,
    {timeout:12000});
  return p;
};

console.log('--- the rail button ---');
let p=await open('/');
await step('Facilities is in the rail',async()=>{
  const labels=await p.$$eval('#nav button[data-go]',n=>n.map(x=>x.dataset.go));
  console.log('       '+labels.join(', '));
  if(!labels.includes('facilities'))throw new Error('not in the rail');
});
await step('clicking it embeds the app, not Settings',async()=>{
  await p.click('#nav button[data-go="facilities"]');
  await p.waitForSelector('.embed-wrap iframe',{timeout:6000});
  const txt=await p.textContent('#main');
  if(/Prototype controls|Type colours/.test(txt))
    throw new Error('it rendered the Settings page');
  const src=await p.getAttribute('.embed-wrap iframe','src');
  console.log('       iframe src: '+src);
  if(!src.includes('facilities.mosaic.org'))throw new Error('wrong src');
  if(!src.includes('embed=portal'))throw new Error('missing embed=portal');
  if(!src.includes('page=requests'))throw new Error('missing page=requests');
});
await step('the URL becomes /facilities',async()=>{
  const u=await p.evaluate(()=>location.pathname);
  if(u!=='/facilities')throw new Error('path is '+u);
});
await step('the sub-menu lists its pages',async()=>{
  const subs=await p.$$eval('#nav .subnav button',n=>n.map(x=>x.textContent.trim()));
  console.log('       '+subs.join(' | '));
  if(subs.length!==4)throw new Error('expected 4, got '+subs.length);
});
await step('a sub-menu click changes the page the iframe loads',async()=>{
  await p.click('#nav .subnav button:has-text("Calendar")');
  await p.waitForFunction(()=>{
    const f=document.querySelector('.embed-wrap iframe');
    return f&&f.src.includes('page=calendar');},{timeout:6000});
  const src=await p.getAttribute('.embed-wrap iframe','src');
  console.log('       '+src);
});
await p.screenshot({path:'portal-facilities.png'});
await p.close();

console.log('--- deep link ---');
p=await open('/facilities');
await step('/facilities boots straight into it',async()=>{
  await p.waitForSelector('.embed-wrap iframe',{timeout:6000});
  const on=await p.$$eval('#nav button.on',n=>n.map(x=>x.dataset.go));
  if(!on.includes('facilities'))throw new Error('rail shows '+on.join(','));
});
await p.close();

console.log('--- facility bookings on the calendar ---');
p=await open('/calendar');
await step('the Facility bookings chip is there',async()=>{
  const chips=await p.$$eval('.filters .chip',n=>n.map(x=>x.textContent.trim()));
  console.log('       '+chips.join(' | '));
  if(!chips.some(c=>/Facility bookings/.test(c)))throw new Error('no chip');
});
await step('the bookings actually land in the calendar',async()=>{
  const got=await p.evaluate(()=>EVENTS.filter(e=>e.type==='facility').map(e=>e.title+' ['+e.status+'] '+e.detail));
  got.forEach(g=>console.log('       '+g));
  if(got.length!==3)throw new Error('expected 3 bookings, got '+got.length);
  if(!got.some(g=>/\[waiting\]/.test(g)))throw new Error('the submitted one should draw as waiting');
});
await step('they use the blocked window, not the event times',async()=>{
  const r=await p.evaluate(()=>{
    const b=window.__BOOKINGS.find(x=>x.ref==='EV-1011');
    const e=EVENTS.find(x=>x.id==='fac:'+b.id);
    const hh=new Date(b.block_start).toLocaleTimeString([],{hour:'numeric',minute:'2-digit'});
    return {detail:e.detail, blockHour:hh};
  });
  console.log('       detail says "'+r.detail+'", block starts '+r.blockHour);
  if(!r.detail.includes(r.blockHour))
    throw new Error('the detail line is not showing the blocked start');
});
await step('a chip click filters them off again',async()=>{
  const before=await p.$$eval('.ev,.evchip,[data-ev]',n=>n.length);
  await p.click('.filters .chip:has-text("Facility bookings")');
  await p.waitForTimeout(300);
  const has=await p.evaluate(()=>S.filters.has('facility'));
  if(has)throw new Error('the filter did not come off');
});
await p.screenshot({path:'portal-calendar.png'});
await p.close();

console.log(errs.length?'\nJS errors:\n  '+errs.join('\n  '):'\nJS errors: none');
console.log(bad?bad+' FAILED':'all good');
await b.close();
process.exitCode=(bad||errs.length)?1:0;
