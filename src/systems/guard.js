export const TOKEN_CAPACITY=10;
export const TOKEN_REFILL_MS=2000;

export class GuardRateLimiter{
  constructor(store){this.store=store;if(!this.store.data.guard_state||typeof this.store.data.guard_state!=="object"||Array.isArray(this.store.data.guard_state))this.store.data.guard_state={};this.lastPrune=new Map();this.bucketCounts=new Map();}
  bucket(guildId,actorId,kind,now=Date.now()){
    let guild=this.store.data.guard_state[guildId];
    if(!guild||typeof guild!=="object"||Array.isArray(guild))guild=this.store.data.guard_state[guildId]={users:{},bots:{},incidents:{}};
    if(!guild.users||typeof guild.users!=="object"||Array.isArray(guild.users)){guild.users={};this.bucketCounts.delete(guildId+":user");}
    if(!guild.bots||typeof guild.bots!=="object"||Array.isArray(guild.bots)){guild.bots={};this.bucketCounts.delete(guildId+":bot");}
    const collection=kind==="bot"?guild.bots:guild.users;
    const collectionKey=guildId+":"+kind;
    if(now-(this.lastPrune.get(collectionKey)||0)>=60000){
      let count=this.bucketCounts.get(collectionKey);
      if(count===undefined)count=Object.keys(collection).length;
      for(const [id,value] of Object.entries(collection)){
        if(!value||typeof value!=="object"||now-(Number(value.last_consumed)||Number(value.updated_at)||now)>7*86400000){
          delete collection[id];count=Math.max(0,count-1);
        }
      }
      this.bucketCounts.set(collectionKey,count);
      this.lastPrune.set(collectionKey,now);
      if(this.lastPrune.size>5000)this.lastPrune.delete(this.lastPrune.keys().next().value);
    }
    let state=collection[actorId];
    if(!state||typeof state!=="object"||Array.isArray(state)){
      const existed=Object.hasOwn(collection,actorId);
      let count=this.bucketCounts.get(collectionKey);
      if(count===undefined)count=Object.keys(collection).length;
      if(!existed&&count>=20000){
        const keys=Object.keys(collection),remove=Math.max(1,keys.length-18000+1);
        for(let index=0;index<remove;index++)delete collection[keys[index]];
        count=Math.max(0,keys.length-remove);
      }
      state=collection[actorId]={tokens:TOKEN_CAPACITY,updated_at:now,last_activity:0};
      this.bucketCounts.set(collectionKey,count+(existed?0:1));
      if(this.bucketCounts.size>5000)this.bucketCounts.delete(this.bucketCounts.keys().next().value);
    }
    state.tokens=Math.max(0,Math.min(TOKEN_CAPACITY,Number.isInteger(state.tokens)?state.tokens:TOKEN_CAPACITY));
    state.updated_at=Math.min(now,Number.isFinite(state.updated_at)?state.updated_at:now);
    state.last_activity=Math.min(now,Number.isFinite(state.last_activity)?state.last_activity:0);
    return state;
  }
  consume(guildId,actorId,kind="user",now=Date.now()){
    const state=this.bucket(guildId,actorId,kind,now);
    if(kind==="bot"){
      const refillStart=(state.last_activity||0)+TOKEN_REFILL_MS;
      if((state.last_activity||0)>0&&now>=refillStart){
        const gained=1+Math.floor((now-refillStart)/TOKEN_REFILL_MS);
        state.tokens=Math.min(TOKEN_CAPACITY,(state.tokens??TOKEN_CAPACITY)+gained);
        state.updated_at=refillStart+(gained-1)*TOKEN_REFILL_MS;
      }
      state.last_activity=now;
    }else{
      const elapsed=Math.max(0,now-(state.updated_at||now));
      const gained=Math.floor(elapsed/TOKEN_REFILL_MS);
      if(gained){state.tokens=Math.min(TOKEN_CAPACITY,(state.tokens??TOKEN_CAPACITY)+gained);state.updated_at=(state.updated_at||now)+gained*TOKEN_REFILL_MS;}
      if(state.locked&&state.tokens>=TOKEN_CAPACITY)state.locked=false;
    }
    const allowed=kind==="user"?(!state.locked&&state.tokens>0):state.tokens>0;
    if(allowed){
      state.tokens--;
      if(kind==="user"&&state.tokens===0)state.locked=true;
    }
    state.last_consumed=now;
    this.store.queueSave?.();
    const retryAfterMs=allowed?0:(kind==="bot"?Math.max(TOKEN_REFILL_MS,(state.last_activity||now)+TOKEN_REFILL_MS-now):Math.max(1,(state.updated_at||now)+(TOKEN_CAPACITY-(state.tokens??0))*TOKEN_REFILL_MS-now));
    return {allowed,tokens:state.tokens,retryAfterMs,locked:kind==="user"&&Boolean(state.locked)};
  }
}
