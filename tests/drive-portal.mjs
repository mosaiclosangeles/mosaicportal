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
  if(/Prototype controls|Calendar colours/.test(txt))
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

console.log('--- metrics tabs on the rail ---');
// Four edits, not one (see CLAUDE.md). The easiest to miss is the closest()
// list at the top of the click handler: without [data-mp] there, the sub-menu
// renders and does nothing at all.
await step('Metrics puts its six views on the rail',async()=>{
  await p.click('#nav button[data-go="numbers"]'); await p.waitForTimeout(400);
  const subs=await p.$$eval('#nav .subnav button',n=>n.map(x=>x.textContent.trim()));
  console.log('       '+subs.join(' | '));
  const want=['Overview','Campuses','Kids + Future','Trends','Report','History'];
  if(subs.join('|')!==want.join('|'))throw new Error('got '+subs.join(' | '));
});
await step('and a click carries the view into the frame',async()=>{
  await p.click('#nav .subnav button:has-text("Trends")');
  await p.waitForFunction(()=>{const f=document.querySelector('.embed-wrap iframe');
    return f&&f.src.includes('view=trends');},{timeout:5000});
  const on=await p.$$eval('#nav .subnav button.on',n=>n.map(x=>x.textContent.trim()));
  console.log('       '+await p.getAttribute('.embed-wrap iframe','src'));
  if(on.join()!=='Trends')throw new Error('the rail did not follow: '+on.join());
});
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
// Three sources, not five — Loyda's cut, 8 Sep 2026. Asserted because the
// last two label decisions on this calendar were undone by a later session
// that had no way to know they were decisions.
await step('the calendar offers three sources and no more',async()=>{
  const chips=await p.$$eval('.filters .chip',n=>n.map(x=>x.textContent.trim()));
  console.log('       '+chips.join(' | '));
  const want=['Mosaic Calendar','Staff','Facilities','All'];
  if(chips.join('|')!==want.join('|'))
    throw new Error('expected '+want.join(' | ')+', got '+chips.join(' | '));
});
await step('comms is not a calendar source',async()=>{
  const leaks=await p.evaluate(()=>laneOf({type:'comms',title:'x'})!==null||shown({type:'comms',title:'x'}));
  if(leaks)throw new Error('comms is back on the calendar');
});
/* The rule, not the mechanism: rows mean what the thing IS, not which system
   stores it. Routing on the source is what put Mosaic Future under Staff. */
await step('rows route on what the entry is, not where it came from',async()=>{
  const r=await p.evaluate(()=>{
    const lane=(type,title)=>laneOf({type,title});
    return {
      board:      lane('event','Men\u2019s Camp'),
      churchInOutlook: lane('other','Mosaic Future'),
      welcome:    lane('other','Welcome to Mosaic'),
      bibleStudy: lane('other','Regional Bible Study PM Staff Lead'),
      huddle:     lane('other','Team Huddle'),
      staffZoom:  lane('other','Staff Zoom Meeting'),
      bday:       lane('other',"Jonathan Suarez' Bday"),
      pto:        lane('away','Cheryl - PTO'),
      booking:    lane('facility','Rialto Auditorium')
    };
  });
  console.log('       '+JSON.stringify(r));
  const want={board:'mosaic',churchInOutlook:'mosaic',welcome:'mosaic',bibleStudy:'mosaic',
              huddle:'staff',staffZoom:'staff',bday:'staff',pto:'staff',booking:'fac'};
  for(const k of Object.keys(want))
    if(r[k]!==want[k])throw new Error(k+' should be '+want[k]+', got '+r[k]);
});
// A Bible study whose title happens to contain "Staff Lead" must not be filed
// as staff business — that is why INTERNAL matches phrases, not bare words.
// The stub has no planning rows, so feed mapLive one rather than assert
// nothing. A run used to go to CAMPAIGNS and return: a bar with nothing behind
// it, which is why clicking Men's Camp opened the shared calendar's bare copy.
await step('a run on the board is clickable, not only a bar',async()=>{
  const r=await p.evaluate(()=>{
    // mapLive rebuilds EVENTS and CAMPAIGNS from scratch, so put the stub's
    // own data back afterwards or every check below this one loses its
    // bookings.
    const keepE=EVENTS.slice(), keepC=CAMPAIGNS.slice();
    mapLive([{id:'t1',date:'2026-09-11',date_end:'2026-09-13',title:"Men's Camp",
              campus:'LA',level:'Level 1',owners:['David'],phase_now:'Pre-launch',
              status:'On track',description:'x'}],[]);
    const run=EVENTS.find(e=>e.id==='pm:t1');
    const out={bar:CAMPAIGNS.some(c=>c.title==="Men's Camp"),
            clickable:!!run, dateEnd:run&&run.dateEnd, owner:run&&run.owner,
            phase:run&&run.phase, lane:run&&laneOf(run)};
    EVENTS.length=0; keepE.forEach(x=>EVENTS.push(x));
    CAMPAIGNS.length=0; keepC.forEach(x=>CAMPAIGNS.push(x));
    return out;
  });
  console.log('       '+JSON.stringify(r));
  if(!r.bar)throw new Error('the run lost its bar');
  if(!r.clickable)throw new Error('the run is a bar with nothing to click');
  if(r.dateEnd!=='2026-09-13')throw new Error('the run lost its end date');
  if(r.owner!=='David'||r.phase!=='Pre-launch')
    throw new Error('the clickable run lost the board record: '+JSON.stringify(r));
  if(r.lane!=='mosaic')throw new Error('a board run should be church, got '+r.lane);
});
// One card per event, not one line per calendar. The apostrophe rule has its
// own check because getting it wrong is silent: "Men's Camp" and "Mens Camp"
// simply stay two cards and the week looks twice as busy as it is.
await step('the same event from three calendars normalises to one name',async()=>{
  const r=await p.evaluate(()=>({
    board:normTitle("Men's Camp"),
    outlook:normTitle("Mens Camp"),
    prefixed:normTitle("MON 09/07 Mens Camp"),
    different:normTitle("Choir")===normTitle("Choir Rehearsal")
  }));
  console.log('       '+JSON.stringify(r));
  if(!(r.board===r.outlook&&r.outlook===r.prefixed))
    throw new Error('these should all be one event: '+JSON.stringify(r));
  if(r.different)throw new Error('Choir and Choir Rehearsal must stay separate');
});
/* A comm belongs to an event by SUBJECT, not by date. Hannita, 10 Sep: "a team
   Huddle has nothing to do with an ERM text… For the men's event it will be a
   men's text or the men's email, even if it was a past date or a future date."
   Both earlier rules failed silently in opposite directions — same-day hung two
   ERM sends off a staff birthday, exact-title matched nothing at all — so the
   three cases that drove the rule are asserted by name. */
await step('comms attach by subject, not by the day they go out',async()=>{
  const r=await p.evaluate(()=>({
    ermVsHuddle:  commRelated({title:'ERM Text'},{title:'Team Huddle'}),
    bibleStudies: commRelated({title:'Bible Studies'},{title:'Regional Bible Study PM Staff Lead'}),
    mensCamp:     commRelated({title:'MON 09/07 Mens Camp'},{title:"Men's Camp"}),
    ermVsCamp:    commRelated({title:'ERM Text'},{title:"Men's Camp"}),
    // the window is the item's own runway once the mirror carries milestones
    runway: (function(){
      const w=commWindow({date:'2026-10-01',milestones:{kickoff:'2026-08-01',debrief:'2026-11-01'}});
      return [w[0].toISOString().slice(0,10),w[1].toISOString().slice(0,10)];
    })()
  }));
  console.log('       '+JSON.stringify(r));
  if(r.ermVsHuddle)throw new Error('an ERM text is not about a Team Huddle');
  if(r.ermVsCamp)throw new Error('an ERM text is not about Men\'s Camp either');
  if(!r.bibleStudies)throw new Error('"Bible Studies" should reach the Bible Study');
  if(!r.mensCamp)throw new Error('the men\'s text should reach Men\'s Camp');
  if(r.runway[0]!=='2026-08-01'||r.runway[1]!=='2026-11-01')
    throw new Error('the window should be Kick-Off to Debrief, got '+r.runway.join(' to '));
});
/* Merge first, then filter. Backwards, a campus picker on another campus threw
   the board's record away before the merge could reach it, and Men's Camp
   opened as the shared calendar's bare copy — a title, two dates, nothing. */
await step('a campus filter cannot strip a card of its board record',async()=>{
  const r=await p.evaluate(()=>{
    const fac=EVENTS.find(e=>e.type==='facility');
    EVENTS.push({id:'t:board',date:fac.date,dateEnd:fac.date,type:'event',
      title:fac.title,campus:'LA',owner:'David',phase:'Pre-launch',
      boardStatus:'On track',status:'scheduled',desc:'the real record'});
    EVENTS.push({id:'t:outlook',date:fac.date,type:'other',title:fac.title,
      status:'done',campus:''});
    const keep=S.campus;
    S.campus='Mexico';                     // neither LA nor the campus-less copy
    const card=evOn(D(fac.date)).find(c=>(c.parts||[]).length>1);
    const out=card?{parts:card.parts.length,
                    hasBoard:card.parts.some(x=>x.id==='t:board'),
                    phase:partFacts(card).phase}:null;
    S.campus=keep;
    ['t:board','t:outlook'].forEach(id=>EVENTS.splice(EVENTS.findIndex(e=>e.id===id),1));
    return out;
  });
  console.log('       '+JSON.stringify(r));
  if(!r)throw new Error('the card vanished entirely');
  if(!r.hasBoard)throw new Error('the filter threw the board record away');
  if(r.phase!=='Pre-launch')throw new Error('the card lost the phase it should carry');
});
await step('a booking and a board item on one day become one card',async()=>{
  const r=await p.evaluate(()=>{
    const fac=EVENTS.find(e=>e.type==='facility');
    EVENTS.push({id:'test:board',date:fac.date,type:'event',title:fac.title.toUpperCase(),
      status:'scheduled',owner:'David',phase:'Pre-launch',campus:'LA',level:'Level 1',detail:''});
    const card=mergeCards(EVENTS.filter(e=>e.date===fac.date&&shown(e)))
      .find(m=>m.parts.length>1);
    EVENTS.splice(EVENTS.findIndex(e=>e.id==='test:board'),1);
    if(!card)return null;
    return {lead:card.type,parts:card.parts.length,
            facility:!!partFacts(card).facility,phase:partFacts(card).phase};
  });
  console.log('       '+JSON.stringify(r));
  if(!r)throw new Error('nothing merged');
  if(r.lead!=='event')throw new Error('the board should lead, got '+r.lead);
  if(!r.facility)throw new Error('the card lost the room decision');
  if(r.phase!=='Pre-launch')throw new Error('the card lost the phase');
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
// Every entry opens the same card, whatever system it came from. The old
// split — a full page for board items, a narrow drawer for everything else —
// meant the shape of the card told you where the data lived, and the two
// renderers drifted because nothing made them agree.
await step('every entry opens the same card, not a drawer',async()=>{
  const seen=[];
  for(const type of ['facility']){
    const id=await p.evaluate(t=>{const e=EVENTS.find(x=>x.type===t);return e&&e.id;},type);
    if(!id)continue;
    await p.click(`.ev[data-ev="${id}"]`);
    await p.waitForTimeout(350);
    const r=await p.evaluate(()=>({
      section:S.section,
      drawer:document.getElementById('drawer').classList.contains('open')
    }));
    seen.push(type+':'+JSON.stringify(r));
    if(r.section!=='event')throw new Error(type+' did not open the card: '+r.section);
    if(r.drawer)throw new Error(type+' opened the old drawer');
    await p.click('[data-back]'); await p.waitForTimeout(250);
  }
  console.log('       '+seen.join(' | '));
  const gone=await p.evaluate(()=>typeof eventDrawer==='undefined');
  if(!gone)throw new Error('the second renderer is back');
});
await step('a chip click filters them off again',async()=>{
  const before=await p.$$eval('.ev,.evchip,[data-ev]',n=>n.length);
  await p.click('.filters .chip:has-text("Facilities")');
  await p.waitForTimeout(300);
  const has=await p.evaluate(()=>S.filters.has('fac'));
  if(has)throw new Error('the filter did not come off');
});
await p.screenshot({path:'portal-calendar.png'});
await p.close();

console.log(errs.length?'\nJS errors:\n  '+errs.join('\n  '):'\nJS errors: none');
console.log(bad?bad+' FAILED':'all good');
await b.close();
process.exitCode=(bad||errs.length)?1:0;
