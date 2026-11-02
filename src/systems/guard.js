export const TOKEN_CAPACITY=10;
export const TOKEN_REFILL_MS=2000;

export class GuardRateLimiter{
  constructor(store){this.store=store;this.store.data.guard_state||={};}
  bucket(guildId,actorId,kind){
    const guild=this.store.data.guard_state[guildId]||(this.store.data.guard_state[guildId]={users:{},bots:{}});
    guild.users||={};guild.bots||={};
    const collection=kind==="bot"?guild.bots:guild.users;
    let state=collection[actorId];
    if(!state)state=collection[actorId]={tokens:TOKEN_CAPACITY,updated_at:Date.now(),last_activity:0};
    return state;
  }
  consume(guildId,actorId,kind="user",now=Date.now()){
    const state=this.bucket(guildId,actorId,kind);
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
    }
    const allowed=state.tokens>0;
    if(allowed)state.tokens--;
    state.last_consumed=now;
    this.store.queueSave?.();
    return {allowed,tokens:state.tokens,retryAfterMs:allowed?0:(kind==="bot"?Math.max(TOKEN_REFILL_MS,(state.last_activity||now)+TOKEN_REFILL_MS-now):Math.max(1,TOKEN_REFILL_MS-(now-(state.updated_at||now)) ))};
  }
}
