#!/usr/sbin/dtrace -s

#pragma D option stackframes=100
#pragma D option defaultargs

profile:::profile-999
/arg0/
{
	@[stack(), (uint64_t)curthread, pid, tid, execname, 1] = sum(1000);
}

sched:::off-cpu
{
	self->start = timestamp;
}

sched:::on-cpu
/(this->start = self->start)/
{
	this->delta = (timestamp - this->start) / 1000;
	@[stack(), (uint64_t)curthread, pid, tid, execname, 0] = sum(this->delta);
	self->start = 0;
}

profile:::tick-60s,
dtrace:::END
{
	normalize(@, 1000);
	printa("%kthread:%d pid:%d tid:%d name:%s oncpu:%d ms:%@d\n", @);
	trunc(@);
	exit(0);
}
