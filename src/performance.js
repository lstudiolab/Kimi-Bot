import { monitorEventLoopDelay, performance } from "node:perf_hooks";

const SLOW_INTERACTION_MS=750;
const EVENT_LOOP_WARN_MS=100;
const REPORT_INTERVAL_MS=60_000;

export class PerformanceMonitor {
  constructor(logger) {
    this.logger=logger;
    this.loop=monitorEventLoopDelay({resolution:20});
    this.interactions=new Map();
    this.completed=0;
    this.slow=0;
    this.startedAt=performance.now();
    this.timer=null;
  }
  start() {
    if(this.timer)return;
    this.loop.enable();
    this.timer=setInterval(()=>this.report(),REPORT_INTERVAL_MS);
    this.timer.unref?.();
  }
  begin(interaction) {
    const key=interaction.id;
    this.interactions.set(key,{started:performance.now(),kind:interaction.commandName||interaction.customId||"unknown"});
    return ()=>this.end(key);
  }
  end(key) {
    const record=this.interactions.get(key);
    if(!record)return 0;
    this.interactions.delete(key);
    const duration=performance.now()-record.started;
    this.completed++;
    if(duration>=SLOW_INTERACTION_MS){
      this.slow++;
      this.logger.warn("Slow interaction:",record.kind,Math.round(duration)+"ms");
    }
    return duration;
  }
  report() {
    const p99=this.loop.percentile(99)/1e6;
    const max=this.loop.max/1e6;
    if(p99>=EVENT_LOOP_WARN_MS)this.logger.warn("Event-loop delay is elevated:",{p99_ms:+p99.toFixed(1),max_ms:+max.toFixed(1)});
    else this.logger.debug("Performance interval:",{
      interactions:this.completed,
      slowInteractions:this.slow,
      eventLoopP99Ms:+p99.toFixed(1),
      eventLoopMaxMs:+max.toFixed(1),
      uptimeSeconds:Math.round((performance.now()-this.startedAt)/1000)
    });
    this.completed=0;
    this.slow=0;
    this.loop.reset();
  }
  stop() {
    if(this.timer)clearInterval(this.timer);
    this.timer=null;
    this.loop.disable();
  }
}
