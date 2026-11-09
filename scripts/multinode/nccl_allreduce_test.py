import os,time,torch,torch.distributed as dist
dist.init_process_group("nccl")
r,w,lr=dist.get_rank(),dist.get_world_size(),int(os.environ["LOCAL_RANK"])
torch.cuda.set_device(lr)
x=torch.ones(128*1024*1024,device="cuda",dtype=torch.float32)  # 512 MiB
for _ in range(3): dist.all_reduce(x)
torch.cuda.synchronize(); dist.barrier()
n=10; t=time.time()
for _ in range(n): x.fill_(1.0); dist.all_reduce(x)
torch.cuda.synchronize(); dt=(time.time()-t)/n
if r==0:
    size=x.numel()*4
    print(f"RESULT world={w} allreduce 512MiB: {dt*1000:.1f} ms  busbw={2*(w-1)/w*size/dt/1e9:.1f} GB/s  value_ok={x[0].item()==w}",flush=True)
dist.destroy_process_group()
