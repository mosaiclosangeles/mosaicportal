/* Stands in for the portal's Supabase client so the real index.html can be
   driven in a browser without a sign-in. Same chainable shape the app uses. */
(function(){
const now=new Date();
const iso=(d,h)=>{const x=new Date(now);x.setDate(x.getDate()+d);x.setHours(h||10,0,0,0);return x.toISOString();};

const BOOKINGS=[
  {id:'q1',ref:'EV-1011',title:'Reyes & Calloway — Wedding',request_type:'event',status:'approved',
   campus_name:'Los Angeles',space_name:'Rialto Auditorium',organization:'Reyes & Calloway',
   requester_name:'Marisol Reyes',requested_by_name:'Marisol Reyes',attendees:180,
   block_start:iso(2,15),block_end:iso(2,23),archived_at:null},
  {id:'q2',ref:'FR-1013',title:'Youth band rehearsal',request_type:'facility_use',status:'submitted',
   campus_name:'Los Angeles',space_name:'Rialto Stage',organization:null,
   requester_name:'Hannita',requested_by_name:'Hannita',attendees:25,
   block_start:iso(4,19),block_end:iso(4,22),archived_at:null},
  {id:'q3',ref:'MT-1004',title:'Plumbing / restrooms',request_type:'maintenance',status:'approved',
   campus_name:'Los Angeles',space_name:null,organization:null,
   requester_name:'Alisah',requested_by_name:'Alisah',attendees:null,
   block_start:iso(1,8),block_end:iso(1,17),archived_at:null}
];
window.__BOOKINGS=BOOKINGS;

const PROFILE={id:'me',email:'hannita@mosaic.org',role:'admin',display_name:'Hannita',
  full_name:'Hannita',campus_id:'c1',avatar_url:null,theme:null};

function builder(table){
  let rows = table==='v_fac_requests' ? BOOKINGS.slice()
           : table==='profiles' ? [PROFILE]
           : [];
  const api={
    select(){return api;}, order(){return api;}, limit(){return api;},
    eq(){return api;}, is(){return api;}, in(){return api;}, gte(){return api;}, lte(){return api;},
    neq(){return api;}, not(){return api;}, or(){return api;},
    single(){return Promise.resolve({data:rows[0]||null,error:null});},
    maybeSingle(){return Promise.resolve({data:rows[0]||null,error:null});},
    insert(){return Promise.resolve({data:null,error:null});},
    update(){return {eq(){return Promise.resolve({data:null,error:null});}};},
    delete(){return {eq(){return Promise.resolve({data:null,error:null});}};},
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
  rpc:(name)=>Promise.resolve({data:name==='can'?true:null,error:null}),
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
  if(url.includes('yrviwbqhjcrlxgozrgay'))
    return Promise.resolve(new Response('[]',{status:200,headers:{'Content-Type':'application/json'}}));
  return realFetch(u,o);
};
})();
