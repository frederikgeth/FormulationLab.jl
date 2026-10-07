/* Diagnostic bridge: compile against the headers of the loaded MUMPS library.
 * Julia owns matrix/ordering arrays for the complete handle lifetime.
 * No global solver, MPI initialization, or modification of the installed library.
 */
#include <stdlib.h>
#include <string.h>
#include "dmumps_c.h"
_Static_assert(sizeof(MUMPS_INT) == 4, "32-bit MUMPS integers required");
typedef void (*solver_fn)(DMUMPS_STRUC_C *);
typedef struct { DMUMPS_STRUC_C id; solver_fn run; } lab_factor;
const char *lab_mumps_version(void) { return MUMPS_VERSION; }

void *lab_mumps_factor(void *entry, int n, int nz, int *rows, int *cols,
                      double *values, int *permutation, int controlled,
                      int *info, int *permutation_out) {
    lab_factor *h = calloc(1, sizeof(*h));
    if (!h) { info[0] = -9999; return NULL; }
    h->run = (solver_fn)entry;
    h->id.par=1; h->id.sym=2; h->id.comm_fortran=-987654;
    h->id.job=-1; h->run(&h->id);
    if (h->id.infog[0] < 0) goto done;
    for (int i=0; i<4; ++i) h->id.icntl[i]=0;
    h->id.n=n; h->id.nnz=nz;
    h->id.irn=rows; h->id.jcn=cols; h->id.a=values;
    h->id.icntl[5]=controlled ? 0 : 7;
    h->id.icntl[6]=controlled ? 1 : 7;
    h->id.icntl[7]=controlled ? 0 : 77;
    h->id.icntl[9]=0;    /* no internal refinement */
    h->id.icntl[12]=1;   /* sequential root, as in Ipopt */
    h->id.icntl[13]=1000;
    h->id.icntl[23]=0;   /* no null-pivot detection/substitution */
    h->id.icntl[27]=1;   /* sequential analysis */
    h->id.icntl[34]=0;   /* no BLR */
    h->id.cntl[0]=1e-6;
    h->id.perm_in=controlled ? permutation : NULL;
    h->id.job=1; h->run(&h->id);
    if (h->id.infog[0] < 0) goto done;
    memcpy(permutation_out,h->id.sym_perm,n*sizeof(int));
    h->id.job=2; h->run(&h->id);
done:
    memcpy(info,h->id.infog,80*sizeof(int));
    return h;
}
int lab_mumps_solve(void *handle, double *rhs) {
    lab_factor *h=handle;
    h->id.nrhs=1; h->id.lrhs=h->id.n; h->id.rhs=rhs;
    h->id.job=3; h->run(&h->id);
    h->id.rhs=NULL;
    return h->id.infog[0];
}
void lab_mumps_free(void *handle) {
    if (!handle) return;
    lab_factor *h=handle;
    h->id.job=-2; h->run(&h->id); free(h);
}
