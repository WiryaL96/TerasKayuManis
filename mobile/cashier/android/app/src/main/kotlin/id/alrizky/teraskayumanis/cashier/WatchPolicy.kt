package id.alrizky.teraskayumanis.cashier

/** Pure state policy shared by the real service and JVM regression tests. */
class WatchPolicy {
    private var active = false
    private var generation = 0L
    private var inFlight: Long? = null
    @Synchronized fun start(): Long { active = true; generation++; return generation }
    @Synchronized fun stop() { active = false; generation++ }
    @Synchronized fun acquire(): Long? {
        if (!active || inFlight != null) return null
        return generation.also { inFlight = it }
    }
    @Synchronized fun complete(ticket: Long): Boolean {
        if (inFlight == ticket) inFlight = null
        return active && ticket == generation
    }
    @Synchronized fun current(ticket: Long) = active && ticket == generation
}
