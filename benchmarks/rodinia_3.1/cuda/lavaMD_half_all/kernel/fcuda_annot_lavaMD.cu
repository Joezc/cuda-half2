#include <fcuda.h>
#include "main.h"
#include <string.h>
#include <math.h>
#pragma FCUDA GRID x_dim=128
#pragma FCUDA COREINFO num_cores=1 pipeline=yes
#pragma FCUDA PORTMERGE remove_port_name=d_box_gpu_offset port_id=0
#pragma FCUDA PORTMERGE remove_port_name=d_box_gpu_nn port_id=1
#pragma FCUDA PORTMERGE remove_port_name=d_box_gpu_number port_id=1
#pragma FCUDA PORTMERGE remove_port_name=d_rv_gpu port_id=2
#pragma FCUDA PORTMERGE remove_port_name=d_qv_gpu port_id=2
#pragma FCUDA PORTMERGE remove_port_name=d_fv_gpu port_id=2
__global__ void kernel_gpu_cuda(//par_str d_par_gpu,
    fp alpha,
    //dim_str d_dim_gpu,
    long number_boxes,
    long *d_box_gpu_offset,
    int *d_box_gpu_nn,
    int *d_box_gpu_number,
    //box_str *d_box_gpu,
    fp *d_rv_gpu,
    fp *d_qv_gpu,
    fp *d_fv_gpu)
{

  int bx = blockIdx.x;	// get current horizontal block index (0-n)
  int tx = threadIdx.x;	// get current horizontal thread index (0-n)
  //int wtx = tx;

  //if(bx < d_dim_gpu.number_boxes) {
  if (bx < number_boxes) {
    ///*
    // parameters
    //fp a2 = 2.0 * d_par_gpu.alpha * d_par_gpu.alpha;
    fp a2 = 2.0 * alpha * alpha;

    // home box
    int first_i;
    fp* rA;
    fp* fA;
    __shared__ fp rA_shared[4 * 100];
    __shared__ fp fA_shared[4 * 100];

    // nei box
    int pointer;
    int k = 0;
    int first_j;
    fp* rB;
    fp* qB;
    int j = 0;
    __shared__ fp rB_shared[4 * 100];
    __shared__ fp qB_shared[100];

    // common
    fp r2;
    fp u2;
    fp vij;
    fp fs;
    fp fxij;
    fp fyij;
    fp fzij;
    THREE_VECTOR d;
    //*/
    // home box - box parameters
    first_i = d_box_gpu_offset[bx]; //d_box_gpu[bx].offset;

//#pragma FCUDA COMPUTE cores=[1] name=compute begin unroll=1 mpart=1 array_split=[]	
    // home box - distance, force, charge and type parameters
    //rA = &d_rv_gpu[first_i];
    //fA = &d_fv_gpu[first_i];

    // home box - shared memory
//#pragma FCUDA TRANSFER cores=[1] type=burst dir=[0|0] begin name=fetch1 pointer=[d_rv_gpu|d_fv_gpu] size=[400|400] unroll=1 mpart=1 array_split=[rA_shared]
    //while (wtx < NUMBER_PAR_PER_BOX) {
    rA_shared[tx] = d_rv_gpu[4 * first_i + tx]; //rA[wtx];
    fA_shared[tx] = d_fv_gpu[4 * first_i + tx];
    //wtx = wtx + NUMBER_THREADS;
    //}
    //wtx = tx;
//#pragma FCUDA TRANSFER cores=[1] type=burst dir=[0|0] end name=fetch1 pointer=[d_rv_gpu|d_fv_gpu] size=[400|400] unroll=1 mpart=1 array_split=[rA_shared]

    // synchronize threads  - not needed, but just to be safe
   // __syncthreads();

    // loop over neiing boxes of home box
    for (k = 0; k < 1 + d_box_gpu_nn[bx] /*d_box_gpu[bx].nn*/; k++) {

      if(k==0)
        pointer = bx;					// set first box to be processed to home box
      else
        //pointer = d_box_gpu[bx].nei[k-1].number;		// remaining boxes are nei boxes
        pointer = d_box_gpu_number[bx * 26 + k - 1];
      // nei box - box parameters
      first_j = d_box_gpu_offset[pointer]; //d_box_gpu[pointer].offset;

      // nei box - distance, (force), charge and (type) parameters
      //rB = &d_rv_gpu[first_j];
      //qB = &d_qv_gpu[first_j];

      // nei box - shared memory
#pragma FCUDA TRANSFER cores=[1] type=burst dir=[0|0] begin name=fetch2 pointer=[d_rv_gpu|d_qv_gpu] size=[400|100] unroll=1 mpart=1 array_split=[rA_shared]
      //while(wtx < NUMBER_PAR_PER_BOX) {
      rB_shared[tx] = d_rv_gpu[4 * first_j + tx];
      qB_shared[tx] = d_qv_gpu[first_j + tx];
      //wtx = wtx + NUMBER_THREADS;
      //}
      //wtx = tx;
#pragma FCUDA TRANSFER cores=[1] type=burst dir=[0|0] end name=fetch2 pointer=[d_rv_gpu|d_qv_gpu] size=[400|100] unroll=1 mpart=1 array_split=[rA_shared]
      // synchronize threads because in next section each thread accesses data brought in by different threads here
     // __syncthreads();

      // loop for the number of particles in the home box

#pragma FCUDA COMPUTE cores=[1] begin name=compute unroll=1 mpart=1 array_split=[rA_shared] //shape=[100]
      int wtx = tx;
      if (wtx < NUMBER_PAR_PER_BOX) {
        //while (wtx < NUMBER_PAR_PER_BOX) {

        // loop for the number of particles in the current nei box
        for (j=0; j< 4 *NUMBER_PAR_PER_BOX; j+=4){
          r2 = (fp)rA_shared[4 * wtx] + (fp)rB_shared[j] - DOT((fp)rA_shared, 4 * wtx, (fp)rB_shared, j); //DOT((fp)rA_shared[4 * wtx],(fp)rB_shared[j]);
          u2 = a2*r2;
          vij = exp(-u2);
          fs = 2*vij;

          d.x = (fp)rA_shared[4 * wtx + 1]  - (fp)rB_shared[j + 1];
          fxij = fs*d.x;
          d.y = (fp)rA_shared[4 * wtx + 2]  - (fp)rB_shared[j + 2];
          fyij = fs*d.y;
          d.z = (fp)rA_shared[4 * wtx + 3]  - (fp)rB_shared[j + 3];
          fzij = fs*d.z;

          //d_fv_gpu[first_i + wtx].v += (fp)((fp)qB_shared[j]*vij);
          fA_shared[4 * wtx] += (fp)((fp)qB_shared[j / 4]*vij);
          //d_fv_gpu[first_i + wtx].x += (fp)((fp)qB_shared[j]*fxij);
          fA_shared[4 * wtx + 1] += (fp)((fp)qB_shared[j / 4]*fxij);
          //d_fv_gpu[first_i + wtx].y += (fp)((fp)qB_shared[j]*fyij);
          fA_shared[4 * wtx + 2] += (fp)((fp)qB_shared[j / 4]*fyij);
          //d_fv_gpu[first_i + wtx].z += (fp)((fp)qB_shared[j]*fzij);
          fA_shared[4 * wtx + 3] += (fp)((fp)qB_shared[j / 4]*fzij);
        }

        // increment work thread index
        //wtx = wtx + NUMBER_THREADS;

      }
      // reset work index
      //wtx = tx;

      // synchronize after finishing force contributions from current nei box not to cause conflicts when starting next box
      __syncthreads();
#pragma FCUDA COMPUTE cores=[1] end name=compute unroll=1 mpart=1 array_split=[rA_shared] //shape=[100]
      }

#pragma FCUDA TRANSFER cores=[1] dir=[1] type=burst begin name=write pointer=[d_fv_gpu] size=[400] unroll=1 mpart=1 array_split=[rA_shared]
      d_fv_gpu[4 * first_i + tx] = fA_shared[tx];
#pragma FCUDA TRANSFER cores=[1] dir=[1] type=burst end name=write pointer=[d_fv_gpu] size=[400] unroll=1 mpart=1 array_split=[rA_shared]
//#pragma FCUDA COMPUTE cores=[1] name=compute end unroll=1 mpart=1 array_split=[]
    }

  }
