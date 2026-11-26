/* Stands in for the portal's Supabase client so the real index.html can be
   driven in a browser without a sign-in. Same chainable shape the app uses. */
(function(){
const now=new Date();
const iso=(d,h)=>{const x=new Date(now);x.setDate(x.getDate()+d);x.setHours(h||10,0,0,0);return x.toISOString();};

const BOOKINGS=[
  {id:'q1',ref:'EV-1011',title:'Reyes & Calloway — Wedding',request_type:'event',status:'approved',
   campus_name:'Los Angeles',space_name:'Rialto Auditorium',organization:'Reyes & Calloway',
   requester_name:'Marisol Reyes',requested_by_name:'Marisol Reyes',attendees:180,
   is_external:true,requested_by:'u-marisol',task_count:5,task_done_count:2,
   block_start:iso(2,15),block_end:iso(2,23),archived_at:null},
  {id:'q2',ref:'FR-1013',title:'Youth band rehearsal',request_type:'facility_use',status:'submitted',
   campus_name:'Los Angeles',space_name:'Rialto Stage',organization:null,
   requester_name:'Hannita',requested_by_name:'Hannita',attendees:25,
   is_external:false,requested_by:'me',task_count:0,task_done_count:0,
   block_start:iso(4,19),block_end:iso(4,22),archived_at:null},
  {id:'q3',ref:'MT-1004',title:'Plumbing / restrooms',request_type:'maintenance',status:'approved',
   campus_name:'Los Angeles',space_name:null,organization:null,
   requester_name:'Alisah',requested_by_name:'Alisah',attendees:null,
   is_external:false,requested_by:'u-alisah',task_count:0,task_done_count:0,
   block_start:iso(1,8),block_end:iso(1,17),archived_at:null},
  // A repair the signed-in person reported, with nobody lined up yet.
  {id:'q4',ref:'MX-1005',title:'AC not cooling in the green room',request_type:'maintenance',status:'submitted',
   campus_name:'Los Angeles',space_name:'Green Room',organization:null,
   requester_name:'Hannita',requested_by_name:'Hannita',attendees:null,
   is_external:false,requested_by:'me',task_count:0,task_done_count:0,
   block_start:iso(5,9),block_end:iso(5,10),archived_at:null}
];
/* The repair rows behind the maintenance requests. q3's quote has been shared
   with Alisah and not answered, so it is the approver's to look at. */
const REPAIRS=[
  {request_id:'q3',pro_name:'Rafael (Westside Plumbing)',visit_at:iso(-3,9),visit_done_at:iso(-3,10),
   quote_at:iso(-2,12),quote_shared_at:iso(-2,12),quote_decision:null,
   work_at:null,work_done_at:null,paid_at:null}
];
window.__BOOKINGS=BOOKINGS;

const PROFILE={id:'me',email:'hannita@mosaic.org',role:'admin',display_name:'Hannita',
  full_name:'Hannita',campus_id:'c1',avatar_url:null,theme:null};

/* The campuses the board's short names map onto. Without these campusIdOf()
   answers null for everything, which is the honest reading of "we don't know
   this campus" — but it also silently skips every check keyed on a campus, so
   an empty table here made the attendance assertions pass by not running. */
const CAMPUS_ROWS=[
  {id:'c1',name:'Los Angeles',active:true},
  {id:'c2',name:'New York City',active:true},
  {id:'c3',name:'Mexico',active:true}
];
/* THE STAFF DIRECTORY. Made-up people, one in each state the Users list
   draws: signed in (the signed-in admin herself), invite sent, invite saved,
   no invite — plus a portal account and a saved invite the directory does not
   know, which must still be listed rather than dropping off the page. */
const DIR_ROWS=[
  {id:'d-me',profile_id:'me',name:PROFILE.display_name,email:PROFILE.email,emails_secondary:['me.second@example.org'],
   nicknames:['HC'],title:'Systems lead',campus_id:'c3',campus:'Mexico',location_id:'l-pol',location:'Polanco',
   oversees_all:false,campus_ids_overseen:['c1'],campuses_overseen:['Los Angeles'],ministries:['Systems'],teams:[],
   slack_user_id:'UME',slack_ids_secondary:[],role:'admin',activation:'signed_in',status:'active',pending_invite_id:null,
   last_sign_in_at:iso(-1,9),needs_review:null},
  {id:'d-ivy',profile_id:'u-ivy',name:'Ivy Sent',email:'ivy@example.org',emails_secondary:['ivy.alt@example.org'],nicknames:[],title:null,
   campus_id:'c1',campus:'Los Angeles',location_id:null,location:null,oversees_all:false,campus_ids_overseen:[],campuses_overseen:[],
   ministries:['Kids'],teams:[],slack_user_id:'UIVY',slack_ids_secondary:[],role:'staff',activation:'invite_sent',status:'not activated',
   pending_invite_id:null,last_sign_in_at:null,needs_review:null},
  {id:'d-sam',profile_id:null,name:'Sam Saved',email:'sam@example.org',emails_secondary:['sam.home@example.org'],nicknames:[],title:'Producer',
   campus_id:'c2',campus:'New York City',location_id:null,location:null,oversees_all:false,campus_ids_overseen:[],campuses_overseen:[],
   ministries:['Production','Creative'],teams:[],slack_user_id:'USAM',slack_ids_secondary:[],role:null,activation:'invite_saved',status:'not activated',
   pending_invite_id:'pi-sam',last_sign_in_at:null,needs_review:null},
  {id:'d-nora',profile_id:null,name:'Nora None',email:'nora@example.org',emails_secondary:[],nicknames:[],title:null,
   campus_id:'c1',campus:'Los Angeles',location_id:null,location:null,oversees_all:true,campus_ids_overseen:[],campuses_overseen:[],
   ministries:[],teams:[],slack_user_id:null,slack_ids_secondary:[],role:null,activation:'no_invite',status:'not activated',
   pending_invite_id:null,last_sign_in_at:null,needs_review:'from Slack only — campus and ministries not set'},
  // Ex-staff: their portal account is archived. Not somebody to invite.
  {id:'d-old',profile_id:'u-old',name:'Old Archived',email:'old@example.org',emails_secondary:[],nicknames:[],title:null,
   campus_id:'c1',campus:'Los Angeles',location_id:null,location:null,oversees_all:false,campus_ids_overseen:[],campuses_overseen:[],
   ministries:[],teams:[],slack_user_id:null,slack_ids_secondary:[],role:'volunteer',activation:'archived',status:'archived',
   pending_invite_id:null,last_sign_in_at:null,needs_review:null},
  // No portal profile, but an auth account exists under their email (a
  // Houses login): the server refuses an invite for them.
  {id:'d-hal',profile_id:null,name:'Hal Houses',email:'hal@example.org',emails_secondary:[],nicknames:[],title:null,
   campus_id:'c1',campus:'Los Angeles',location_id:null,location:null,oversees_all:false,campus_ids_overseen:[],campuses_overseen:[],
   ministries:[],teams:[],slack_user_id:'UHAL',slack_ids_secondary:[],role:null,activation:'no_invite',status:'not activated',
   pending_invite_id:null,last_sign_in_at:null,needs_review:null}
];
/* What staff_directory_save_invite() answers, per person. */
const SAVE_INVITE={'d-nora':'saved','d-hal':'has_account'};
/* The raw table, as an admin reads it in the detail drawer. */
const DIR_RAW=DIR_ROWS.map(d=>({id:d.id,full_name:d.name,email:d.email,emails_secondary:d.emails_secondary,nicknames:d.nicknames,
  title:d.title,primary_campus_id:d.campus_id,location_id:d.location_id,campus_ids_overseen:d.campus_ids_overseen,oversees_all:d.oversees_all,
  ministries:d.ministries,teams:d.teams,slack_user_id:d.slack_user_id,slack_ids_secondary:d.slack_ids_secondary,profile_id:d.profile_id,
  needs_review:d.needs_review,source:'corrections'}));
const MINISTRIES=['Kids','Worship','Production','Creative','Systems','Next Gen'].map((name,i)=>({name,sort_order:i,active:true}));
const PENDING=[
  {id:'pi-sam',email:'sam@example.org',name:'Sam Saved',role:'staff',campus_id:'c2',created_at:iso(-3,9)},
  {id:'pi-orphan',email:'orphan@example.org',name:'Otto Orphan',role:'leader',campus_id:'c1',created_at:iso(-2,9)}
];
const OTHER_PROFILES=[
  {id:'u-ivy',full_name:'ivy@example.org',display_name:'Ivy Sent',role:'staff',campus_id:'c1',avatar_url:null,archived_at:null},
  {id:'u-solo',full_name:'solo@example.org',display_name:'Solo Account',role:'leader',campus_id:'c1',avatar_url:null,archived_at:null},
  // A second portal account for Ivy, under her secondary email. No directory row links it.
  {id:'u-ivy2',full_name:'ivy.alt@example.org',display_name:'Ivy Sent',role:'staff',campus_id:'c1',avatar_url:null,archived_at:null},
  {id:'u-old',full_name:'old@example.org',display_name:'Old Archived',role:'volunteer',campus_id:'c1',avatar_url:null,archived_at:iso(-90,9)}
];
const LOCATIONS=[{id:'l-pol',campus_id:'c3',location:'Polanco',active:true},{id:'l-rc',campus_id:'c3',location:'Roma Condesa',active:true}];
/* Every write the page makes, so a test can say exactly what was sent —
   "the self card changed only ministries" is a claim about this list. */
window.__writes=[];
window.__dirFail=false;
function builder(table){
  let rows = table==='v_fac_requests' ? BOOKINGS.slice()
           : table==='profiles' ? [PROFILE].concat(OTHER_PROFILES)
           : table==='campuses' ? CAMPUS_ROWS.slice()
           : table==='fac_repairs' ? REPAIRS.slice()
           : table==='staff_directory' ? DIR_RAW.slice()
           : table==='staff_ministries' ? MINISTRIES.slice()
           : table==='pending_invites' ? PENDING.slice()
           : table==='campus_locations' ? LOCATIONS.slice()
           : [];
  const log=(op,patch)=>({eq(col,val){window.__writes.push({table,op,patch,where:{[col]:val}});return Promise.resolve({data:null,error:null});}});
  const api={
    select(){return api;}, order(){return api;}, limit(){return api;},
    // Only the directory filters for real: the drawer opens one person by id.
    eq(col,val){ if(table==='staff_directory')rows=rows.filter(r=>r[col]===val); return api;},
    is(){return api;}, in(){return api;}, gte(){return api;}, lte(){return api;},
    neq(){return api;}, not(){return api;}, or(){return api;},
    single(){return Promise.resolve({data:rows[0]||null,error:null});},
    maybeSingle(){return Promise.resolve({data:rows[0]||null,error:null});},
    insert(patch){window.__writes.push({table,op:'insert',patch});return Promise.resolve({data:null,error:null});},
    upsert(patch){window.__writes.push({table,op:'upsert',patch});return Promise.resolve({data:null,error:null});},
    update(patch){return log('update',patch);},
    delete(){return log('delete',null);},
    then(res){return Promise.resolve({data:rows,error:null}).then(res);}
  };
  return api;
}
const client={
  auth:{
    getUser:()=>Promise.resolve({data:{user:{id:'me',email:PROFILE.email}}}),
    getSession:()=>Promise.resolve({data:{session:{user:{id:'me'},
      access_token:'stub-access-token',refresh_token:'stub-refresh-token'}}}),
    onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}}),
    signOut:()=>Promise.resolve({}),
    signInWithPassword:()=>Promise.resolve({data:{},error:null}),
    updateUser:()=>Promise.resolve({data:{},error:null}),
    resetPasswordForEmail:()=>Promise.resolve({error:null})
  },
  from:builder,
  rpc:(name,args)=>name==='staff_directory_save_invite'
    ? (window.__writes.push({table:'rpc:'+name,op:'rpc',patch:args}),Promise.resolve({data:SAVE_INVITE[args&&args.p_id]||'not_found',error:null}))
    : name==='staff_directory_list'
    ? Promise.resolve(window.__dirFail?{data:null,error:{message:'function staff_directory_list() does not exist'}}:{data:DIR_ROWS.map(d=>Object.assign({},d)),error:null})
    : Promise.resolve({data:name==='can'?true:null,error:null}),
  functions:{invoke:()=>Promise.resolve({data:{ok:true,configured:true,events:[]},error:null})},
  storage:{from:()=>({createSignedUrls:()=>Promise.resolve({data:[],error:null}),
    upload:()=>Promise.resolve({error:null}), remove:()=>Promise.resolve({error:null})})}
};
window.supabase={createClient:()=>client};

// The planning board and comms are read over plain REST; the portal handles a
// failure gracefully, but empty arrays keep the console quiet.
const realFetch=window.fetch.bind(window);
window.fetch=function(u,o){
  const url=typeof u==='string'?u:(u&&u.url)||'';
  // PM_URL is the Metrics project since 26 Nov 2026; the app's own Metrics reads
  // go through the stubbed client above, so any plain REST fetch is a board read.
  if(url.includes('iknjgrltglwupxjtegfh.supabase.co/rest/v1/'))
    return Promise.resolve(new Response('[]',{status:200,headers:{'Content-Type':'application/json'}}));
  return realFetch(u,o);
};
})();
