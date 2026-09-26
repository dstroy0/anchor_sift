OPENQASM 2.0;
include "qelib1.inc";
// a Bell pair: 00 and 11 tie at 1/2, so no peak can be proved
qreg q[2];
creg c[2];
h q[0];
cx q[0],q[1];
measure q -> c;
