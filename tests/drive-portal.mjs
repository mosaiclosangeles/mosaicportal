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
  await p.waitForSelector('#embedHost iframe:not([hidden])',{timeout:6000});
  const txt=await p.textContent('#main');
  if(/Prototype controls|Calendar colours/.test(txt))
    throw new Error('it rendered the Settings page');
  const src=await p.getAttribute('#embedHost iframe:not([hidden])','src');
  console.log('       iframe src: '+src);
  if(!src.includes('facilities.mosaic.org'))throw new Error('wrong src');
  if(!src.includes('embed=portal'))throw new Error('missing embed=portal');
  if(!src.includes('page=requests'))throw new Error('missing page=requests');
});
await step('the URL becomes /facilities',async()=>{
  const u=await p.evaluate(()=>location.pathname);
  if(u!=='/facilities')throw new Error('path is '+u);
});
await step('the sub-menu lists its pages, and not the form',async()=>{
  const subs=await p.$$eval('#nav .subnav button',n=>n.map(x=>x.textContent.trim()));
  console.log('       '+subs.join(' | '));
  if(subs.length!==3)throw new Error('expected 3, got '+subs.length);
  // "New request" is a card inside the app, not a page on the rail — Hannita,
  // 10 Sep. A rail entry for it would be a second way to the same card.
  if(subs.some(x=>/new request/i.test(x)))throw new Error('the form is back on the rail');
});
await step('a sub-menu click changes the page the iframe loads',async()=>{
  await p.click('#nav .subnav button:has-text("Calendar")');
  await p.waitForFunction(()=>{
    const f=document.querySelector('#embedHost iframe:not([hidden])');
    return f&&f.src.includes('page=calendar');},{timeout:6000});
  const src=await p.getAttribute('#embedHost iframe:not([hidden])','src');
  console.log('       '+src);
});
await p.screenshot({path:'portal-facilities.png'});

/* A number you can open. The count on a Home card is useless on its own if it
   takes a hunt to find out which things it counts, so the card opens the list
   and a row opens the full record — in the same dialog, not a second one over
   the first. */
console.log('--- the Home cards open what they count ---');
await step('a card opens the list of what it is counting',async()=>{
  await p.click('#nav button[data-go="home"]');
  await p.waitForTimeout(400);
  // The stub's board has nothing flagged, so seed one thing to wait on —
  // an empty list would assert nothing about a list.
  await p.evaluate(()=>{
    const e=EVENTS.find(x=>x.type==='event')||EVENTS[0];
    ATTN.push({evId:e.id,title:'No speaker yet — '+e.title,date:e.date,meta:'LA · Carlos'});
    render();
  });
  const counted=await p.$eval('.card[data-cardlist="waiting"] .v',n=>n.textContent.trim());
  await p.click('.card[data-cardlist="waiting"]');
  await p.waitForTimeout(300);
  const r=await p.evaluate(()=>({
    open:document.getElementById('cardWrap').classList.contains('open'),
    rows:document.querySelectorAll('#cardBody .row[data-ev]').length,
    heading:(document.querySelector('#cardBody h1')||{}).textContent
  }));
  console.log('       card says '+counted+', list shows '+r.rows+' — "'+r.heading+'"');
  if(!r.open)throw new Error('the card did not open a list');
  if(String(r.rows)!==counted)
    throw new Error('the list and the number disagree: '+counted+' vs '+r.rows);
});
await step('picking a row opens that record, with a way back',async()=>{
  await p.click('#cardBody .row[data-ev]');
  await p.waitForTimeout(300);
  const r=await p.evaluate(()=>({
    back:!!document.querySelector('#cardBody [data-cardback]'),
    full:(document.getElementById('cardBody').textContent||'').length,
    list:document.querySelectorAll('#cardBody .row[data-ev]').length
  }));
  console.log('       '+JSON.stringify(r));
  if(!r.back)throw new Error('no way back to the list it came from');
  if(r.full<60)throw new Error('the record opened empty');
  const label=(await p.textContent('#cardBody [data-cardback]')).trim();
  console.log('       back reads: "'+label+'"');
  if(/\bto to\b/i.test(label))throw new Error('the back label stutters: '+label);
  await p.click('#cardBody [data-cardback]');
  await p.waitForTimeout(250);
  const back=await p.evaluate(()=>document.querySelectorAll('#cardBody .row[data-ev]').length);
  if(!back)throw new Error('back did not return to the list');
  await p.keyboard.press('Escape');
  await p.waitForTimeout(200);
  await p.evaluate(()=>{ATTN.pop();render();});
});
/* 🐛 Two ways a card claimed a number that was not its own.
   Attendance was summed across every campus (6 Sep read 2,373 — LA 1,051 plus
   Ecuador, Mexico and London), and ANY board item landing on a Sunday got a
   NUMBERS panel, so Kids Training nested under the gathering was handed the
   whole day. */
await step('only a Sunday gathering claims a Sunday attendance',async()=>{
  const r=await p.evaluate(()=>{
    const gathering={type:'event',isGathering:true, campus:'LA',date:'2026-09-06'};
    const nested  ={type:'event',isGathering:false,campus:'LA',date:'2026-09-06'};
    const owns=e=>(e.type==='event'&&!!e.isGathering);
    return {gathering:owns(gathering),nested:owns(nested)};
  });
  console.log('       '+JSON.stringify(r));
  if(!r.gathering)throw new Error('the Sunday gathering lost its numbers');
  if(r.nested)throw new Error('an item nested under the Sunday still claims its attendance');
});
await step('attendance is one campus, never every campus added up',async()=>{
  const r=await p.evaluate(()=>{
    const keep=JSON.stringify(METRICS_BY_CAMPUS), keepC=JSON.stringify(CAMPUSES);
    CAMPUSES=[{id:'c-la',name:'Los Angeles'},{id:'c-mx',name:'Mexico'}];
    METRICS_BY_CAMPUS={'c-la':{'2026-09-06':{a:1051,k:0,n:0}},
                       'c-mx':{'2026-09-06':{a:439, k:0,n:0}}};
    const la=metricsForCampus('LA')['2026-09-06'];
    const mx=metricsForCampus('Mexico')['2026-09-06'];
    const unknown=metricsForCampus('Atlantis')['2026-09-06'];
    METRICS_BY_CAMPUS=JSON.parse(keep); CAMPUSES=JSON.parse(keepC);
    return {la:la&&la.a, mx:mx&&mx.a, unknown:unknown||null};
  });
  console.log('       '+JSON.stringify(r));
  if(r.la!==1051)throw new Error('LA should read its own 1051, got '+r.la);
  if(r.mx!==439)throw new Error('Mexico should read its own 439, got '+r.mx);
  if(r.la+r.mx===2373&&r.la===2373)throw new Error('still summing campuses');
  if(r.unknown)throw new Error('an unknown campus borrowed somebody else\'s numbers');
});
/* Leaving for a section has to take the card with it. With ?item= working, a
   card left open sat on top of the board's own drawer for the same event. */
await step('going to a section closes the card it was clicked from',async()=>{
  await p.click('#nav button[data-go="calendar"]');
  await p.waitForTimeout(300);
  await p.click('#main .cell .ev[data-ev]');
  await p.waitForTimeout(300);
  const opened=await p.evaluate(()=>document.getElementById('cardWrap').classList.contains('open'));
  if(!opened)throw new Error('the card did not open to begin with');
  await p.click('#cardBody [data-go="planning"], #cardBody [data-go="comms"]');
  await p.waitForTimeout(400);
  const r=await p.evaluate(()=>({
    card:document.getElementById('cardWrap').classList.contains('open'),
    scrim:document.getElementById('cardScrim').classList.contains('open'),
    section:S.section}));
  console.log('       '+JSON.stringify(r));
  if(r.card||r.scrim)throw new Error('the card is still over the app it opened');
  await p.click('#nav button[data-go="home"]'); await p.waitForTimeout(300);
});
await step('the New button is one horizontal black button',async()=>{
  const r=await p.evaluate(()=>{
    const b=document.querySelector('.btn-new');
    if(!b)return null;
    const cs=getComputedStyle(b), box=b.getBoundingClientRect();
    return {bg:cs.backgroundColor,w:Math.round(box.width),h:Math.round(box.height),
            text:b.textContent.trim()};
  });
  console.log('       '+JSON.stringify(r));
  if(!r)throw new Error('the New button is gone');
  if(r.h>52)throw new Error('it is still stacked, not horizontal: '+r.h+'px tall');
  if(r.w<=r.h)throw new Error('it is taller than it is wide');
  if(!/^rgb\(17, 17, 17\)$/.test(r.bg))throw new Error('it is not black: '+r.bg);
});
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
/* The rail is a hand-written copy of Metrics' own tabs, so it has to hide the
   same ones Metrics hides. Offering Report to a leader is not a harmless
   extra: Metrics bounces them to Overview, so the tab reads as clicked and
   quietly is not the page they asked for. */
await step('the rail offers a role only the tabs Metrics will serve it',async()=>{
  const r=await p.evaluate(()=>{
    const keep={role:ME.role,preview:ME.preview,previewRole:ME.previewRole,numPath:S.numPath};
    const seen={};
    ['admin','staff','leader','volunteer','campus_pastor'].forEach(role=>{
      ME.role=role; ME.preview=false; ME.previewRole=null;
      seen[role]=metricsNavItems().map(m=>m.page);
    });
    // a view the role cannot see must not reach the frame either
    ME.role='leader'; S.numPath='report';
    pageEmbed('numbers');   // shows the frame and records what it was asked for
    const framed=(FRAMES.numbers.dataset.src.match(/view=([a-z]+)/)||[])[1];
    Object.assign(ME,{role:keep.role,preview:keep.preview,previewRole:keep.previewRole});
    S.numPath=keep.numPath;
    return {seen,framed};
  });
  console.log('       '+JSON.stringify(r.seen));
  console.log('       a leader asking for Report is framed on: '+r.framed);
  if(r.seen.admin.length!==6)throw new Error('an admin should see all six');
  if(r.seen.volunteer.join()!=='overview')throw new Error('a volunteer should see Overview only');
  if(r.seen.leader.join()!=='overview,trends')throw new Error('a leader sees Overview and Trends, got '+r.seen.leader);
  if(r.seen.staff.includes('report'))throw new Error('Report is admin-only in Metrics');
  // campus_pastor is not a role Metrics knows, so it must fall to the most
  // restrictive, exactly as Metrics does — not to everything
  if(r.seen.campus_pastor.join()!=='overview,trends')throw new Error('an unknown role should fall to the most restrictive, got '+r.seen.campus_pastor);
  if(r.framed!=='overview')throw new Error('the frame was sent to a view the rail does not offer: '+r.framed);
});
await step('and a click carries the view into the frame',async()=>{
  await p.click('#nav .subnav button:has-text("Trends")');
  await p.waitForFunction(()=>{const f=document.querySelector('#embedHost iframe:not([hidden])');
    return f&&f.src.includes('view=trends');},{timeout:5000});
  const on=await p.$$eval('#nav .subnav button.on',n=>n.map(x=>x.textContent.trim()));
  console.log('       '+await p.getAttribute('#embedHost iframe:not([hidden])','src'));
  if(on.join()!=='Trends')throw new Error('the rail did not follow: '+on.join());
});
await p.close();

console.log('--- deep link ---');
p=await open('/facilities');
await step('/facilities boots straight into it',async()=>{
  await p.waitForSelector('#embedHost iframe:not([hidden])',{timeout:6000});
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
/* A link somebody actually made beats any guess, and stops the guessing.
   Without this, a comm named for one event could still drift onto another that
   happened to share its words. */
await step('an explicit board_item_id wins over the guess',async()=>{
  const r=await p.evaluate(()=>{
    const camp={title:"Men's Camp",boardId:'k:men-s-camp',date:'2026-09-11'};
    const other={title:'Mens Ministry Night',boardId:'k:other',date:'2026-09-11'};
    const linked={title:'Mens Text',date:'2026-09-05',boardItemId:'k:men-s-camp'};
    const loose ={title:'Mens Camp',date:'2026-09-05'};
    return {
      linkedToIts:   commLink(linked,camp),
      linkedNotOther:commLink(linked,other),   // named for the Camp, so only the Camp
      looseInferred: commLink(loose,camp),
      // an explicit link ignores the window entirely — a debrief email months later
      farOutside:    commLink({title:'x',date:'2027-04-01',boardItemId:'k:men-s-camp'},camp)
    };
  });
  console.log('       '+JSON.stringify(r));
  if(!r.linkedToIts)throw new Error('the linked comm should reach its own event');
  if(r.linkedNotOther)throw new Error('a linked comm must not also drift onto another event');
  if(!r.looseInferred)throw new Error('an unlinked comm should still be inferred');
  if(!r.farOutside)throw new Error('an explicit link should not be bounded by the window');
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
await step('an entry opens a card floating over the calendar it came from',async()=>{
  const seen=[];
  for(const type of ['facility']){
    const id=await p.evaluate(t=>{const e=EVENTS.find(x=>x.type===t);return e&&e.id;},type);
    if(!id)continue;
    await p.click(`.ev[data-ev="${id}"]`);
    await p.waitForTimeout(350);
    const r=await p.evaluate(()=>({
      section:S.section,                      // the calendar is still the page
      card:document.getElementById('cardWrap').classList.contains('open'),
      scrim:document.getElementById('cardScrim').classList.contains('open'),
      grid:!!document.querySelector('#main .calwrap'),   // still drawn behind it
      titled:(document.getElementById('cardBody').textContent||'').trim().length>40,
      drawer:document.getElementById('drawer').classList.contains('open')
    }));
    seen.push(type+':'+JSON.stringify(r));
    if(!r.card)throw new Error(type+' did not open the card');
    if(r.section!=='calendar')throw new Error('the card should not replace the page, got '+r.section);
    if(!r.grid)throw new Error('the calendar was thrown away behind the card');
    if(!r.titled)throw new Error('the card opened empty');
    if(r.drawer)throw new Error(type+' opened the old drawer');
    // Escape closes it, and the calendar is exactly where it was
    await p.keyboard.press('Escape'); await p.waitForTimeout(250);
    const shut=await p.evaluate(()=>({card:document.getElementById('cardWrap').classList.contains('open'),
                                      section:S.section}));
    if(shut.card)throw new Error('Escape did not close the card');
    if(shut.section!=='calendar')throw new Error('closing moved the page to '+shut.section);
  }
  console.log('       '+seen.join(' | '));
  const gone=await p.evaluate(()=>typeof eventDrawer==='undefined');
  if(!gone)throw new Error('the second renderer is back');
});
/* Month and List, and the month is where it opens. Both read the same evOn(),
   so a day that shows two entries in the grid shows the same two in the list. */
await step('the calendar opens on Month and offers only Month and List',async()=>{
  const r=await p.evaluate(()=>({
    views:Array.from(document.querySelectorAll('.seg button')).map(b=>b.textContent.trim()),
    on:(document.querySelector('.seg button.on')||{}).textContent,
    h1:(document.querySelector('#main h1')||{}).textContent
  }));
  console.log('       '+JSON.stringify(r));
  if(r.views.join('|')!=='Month|List')throw new Error('views are '+r.views.join('|'));
  if(r.on!=='Month')throw new Error('it did not open on Month, got '+r.on);
  if(r.h1!=='Calendar')throw new Error('the heading reads '+r.h1);
});
await step('List shows the same days the grid does',async()=>{
  const r=await p.evaluate(()=>{
    const grid=new Set(Array.from(document.querySelectorAll('#main .cell .ev[data-ev]')).map(b=>b.dataset.ev));
    document.querySelector('.seg button[data-view="list"]').click();
    const list=new Set(Array.from(document.querySelectorAll('#main .cl-ev[data-ev]')).map(b=>b.dataset.ev));
    // the grid caps a day at two and hides the rest behind "+N more", so the
    // list is a superset, never a different set
    const missing=[...grid].filter(x=>!list.has(x));
    return {grid:grid.size,list:list.size,missing};
  });
  console.log('       '+JSON.stringify(r));
  if(!r.list)throw new Error('the list drew nothing');
  if(r.missing.length)throw new Error('the list is missing entries the grid shows: '+r.missing.join(', '));
});
/* "Edit in Planning" has to carry the BOARD's id. A merged card leads with
   whichever part ranks first — often the shared calendar's copy — and reading
   the id off that sends Planning nothing, so it opens on its front page. */
await step('Edit in Planning carries the board id, not the lead',async()=>{
  const r=await p.evaluate(()=>{
    const fac=EVENTS.find(e=>e.type==='facility');
    EVENTS.push({id:'pm:k:2026-09:mens-camp',date:fac.date,type:'event',title:fac.title,
      campus:'LA',owner:'David',phase:'Pre-launch',status:'scheduled'});
    EVENTS.push({id:'ol:1',date:fac.date,type:'other',title:fac.title,status:'done'});
    const card=mergeCards(EVENTS.filter(e=>e.date===fac.date&&laneOf(e))).find(c=>(c.parts||[]).length>1);
    const out={parts:(card.parts||[]).length,
               lead:card.id,
               id:pmId(boardPart(card,card))};
    ['pm:k:2026-09:mens-camp','ol:1'].forEach(id=>EVENTS.splice(EVENTS.findIndex(e=>e.id===id),1));
    return out;
  });
  console.log('       '+JSON.stringify(r));
  if(r.id!=='k:2026-09:mens-camp')
    throw new Error('the board id did not come through: "'+r.id+'"');
});
await step('a list row opens the same floating card',async()=>{
  await p.click('#main .cl-ev[data-ev]');
  await p.waitForTimeout(300);
  const open=await p.evaluate(()=>document.getElementById('cardWrap').classList.contains('open'));
  if(!open)throw new Error('the list row did not open the card');
  // a corner, not the centre — the scrim spans the viewport but the card sits
  // on top of the middle of it
  await p.click('#cardScrim',{position:{x:8,y:8}}); await p.waitForTimeout(250);
  const shut=await p.evaluate(()=>!document.getElementById('cardWrap').classList.contains('open'));
  if(!shut)throw new Error('clicking away did not close the card');
  await p.evaluate(()=>{document.querySelector('.seg button[data-view="month"]').click();});
});
/* A LOCATION THAT IS A LINK IS "ONLINE", AND A LINK IS FOLLOWABLE.
   Hannita, 10 Sep: "any card with a link should have the hyperlink", and "if
   an event has a zoom link then location should be ONLINE". Outlook keeps the
   meeting URL in the location field, so the Arena call printed a 70-character
   Zoom address three times on one card and offered no way to click it. */
console.log('--- a link is a link, and a zoom link means Online ---');
const ZOOM='https://us06web.zoom.us/meeting/register/zBMZF-CySGeLrpoiNaKiig';
await step('a location that is only a link reads as Online',async()=>{
  const r=await p.evaluate(z=>({
    pure:placeOf(z),
    hybrid:placeOf('Rialto Auditorium; '+z),
    room:placeOf('Rialto Auditorium'),
    blank:placeOf(''),
    missing:placeOf(null),
    meet:meetLink({detail:z}),
    notMeet:meetLink({detail:'https://facilities.mosaic.org/requests/12'}),
    name:meetName(z),
    teams:meetName('https://teams.microsoft.com/l/meetup-join/x')
  }),ZOOM);
  console.log('       '+JSON.stringify(r));
  if(r.pure!=='Online')throw new Error('a bare zoom link should read Online, got '+JSON.stringify(r.pure));
  if(r.hybrid!=='Rialto Auditorium · Online')
    throw new Error('a hybrid location should keep its room: '+JSON.stringify(r.hybrid));
  if(r.room!=='Rialto Auditorium')throw new Error('a plain room must be left alone');
  if(r.blank||r.missing)throw new Error('no location should stay no location');
  if(r.meet!==ZOOM)throw new Error('the meeting link was not found');
  if(r.notMeet)throw new Error('a facilities link is not a meeting link');
  if(r.name!=='Zoom'||r.teams!=='Teams')throw new Error('wrong name: '+r.name+'/'+r.teams);
});
await step('linkify makes an address clickable and still escapes',async()=>{
  const r=await p.evaluate(z=>({
    anchored:linkify('Join here: '+z).includes('<a href="'+z+'"'),
    escaped:linkify('<img src=x onerror=alert(1)>').indexOf('&lt;img')===0,
    escapedWithUrl:!/<img/.test(linkify('<img> '+z)),
    plain:linkify('Rialto Auditorium')
  }),ZOOM);
  console.log('       '+JSON.stringify(r));
  if(!r.anchored)throw new Error('the address did not become a link');
  if(!r.escaped||!r.escapedWithUrl)throw new Error('linkify let markup through');
  if(r.plain!=='Rialto Auditorium')throw new Error('plain text should pass through unchanged');
});
await step('the card says Online and offers the way in',async()=>{
  await p.evaluate(z=>{
    EVENTS.push({id:'zz1',date:key(TODAY),title:'Arena Call Business Focus',
      type:'other',status:'done',detail:z,owner:'',campus:'',
      link:'https://outlook.office.com/calendar/item/zz1'});
    openCard('zz1');
  },ZOOM);
  await p.waitForTimeout(300);
  const r=await p.evaluate(()=>{
    const b=document.getElementById('cardBody');
    return {sub:b.querySelector('.sub').textContent.trim(),
      rows:[...b.querySelectorAll('.kv')].map(x=>x.textContent.trim()),
      zoomAnchor:!!b.querySelector('.kv a[href*="zoom.us"]'),
      foot:[...b.querySelectorAll('.foot-links a,.foot-links button')].map(x=>x.textContent.trim())};
  });
  console.log('       sub: '+r.sub);
  console.log('       '+r.rows.join(' | '));
  console.log('       '+r.foot.join(' | '));
  if(/zoom\.us/.test(r.sub))throw new Error('the subtitle still prints the URL');
  if(!/Online/.test(r.sub))throw new Error('the subtitle should say Online');
  if(!r.rows.some(x=>/^Where\s*Online$/.test(x.replace(/\s+/g,' '))))
    throw new Error('Where should read Online: '+r.rows.join(' | '));
  if(!r.zoomAnchor)throw new Error('the address is not clickable');
  if(!r.foot.some(x=>x==='Join on Zoom'))throw new Error('no way in: '+r.foot.join(' | '));
  if(!r.foot.some(x=>x==='Open in Outlook'))throw new Error('the Outlook link went missing');
  await p.evaluate(()=>{closeCard();EVENTS.splice(EVENTS.findIndex(x=>x.id==='zz1'),1);});
  await p.waitForTimeout(200);
});
/* The facilities event card asks the portal to switch section rather than open
   a tab (Hannita, 10 Sep). Two halves, and both have to answer: the capability
   ping the frame sends on load — without a reply it renders a plain link and
   opens a tab, which is the behaviour she asked to be rid of — and the move
   itself. Planning is the section that card actually asks for, and it was the
   one section missing from NAV_ALLOWED.
   The frame is a same-origin srcdoc iframe, which the harness's EMBED_TRUSTED
   accepts on localhost exactly as it accepts *.mosaic.org in production. */
await step('a framed app can ask the portal to move, Planning included',async()=>{
  const nav=await p.evaluate(()=>({planning:!!NAV_ALLOWED.planning,
                                   sections:Object.keys(NAV_ALLOWED)}));
  console.log('       navigable: '+nav.sections.join(', '));
  if(!nav.planning)throw new Error('Planning cannot be arrived at — the card will open a tab');
  const got=await p.evaluate(()=>new Promise(res=>{
    const seen=[];
    const on=ev=>{const t=(ev.data||{}).type||'';if(t.startsWith('harness-'))seen.push(t.slice(8));};
    window.addEventListener('message',on);
    const f=document.createElement('iframe');
    f.style.display='none';
    // The frame relays back whatever the portal answers it, because the reply
    // is posted to e.source and never reaches this window.
    f.srcdoc='<scr'+'ipt>window.addEventListener("message",e=>{'+
      'if(e.data&&e.data.type)parent.postMessage({type:"harness-"+e.data.type},"*");});'+
      'parent.postMessage({type:"mosaic-can-navigate"},"*");'+
      'setTimeout(()=>parent.postMessage({type:"mosaic-navigate",section:"planning"},"*"),80);'+
      '</scr'+'ipt>';
    document.body.appendChild(f);
    setTimeout(()=>{
      window.removeEventListener('message',on);f.remove();
      res({seen,section:S.section,book:(S.navBook&&S.navBook.planning)||null});
    },700);
  }));
  console.log('       '+JSON.stringify(got));
  if(!got.seen.includes('mosaic-navigate-ok'))
    throw new Error('the portal never said it can navigate, so the card falls back to a tab');
  if(got.section!=='planning')throw new Error('the portal did not move, it is on '+got.section);
  if(!got.seen.includes('mosaic-navigated'))
    throw new Error('the frame was not told it landed, so it may open a tab as well');
  if(got.book&&got.book.page==='new')
    throw new Error('a bare move opened the new-item form: '+JSON.stringify(got.book));
  // back to the calendar for the checks below
  await p.evaluate(()=>{S.section='calendar';S.navBook=null;render();});
  await p.waitForSelector('.filters .chip',{timeout:6000});
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
