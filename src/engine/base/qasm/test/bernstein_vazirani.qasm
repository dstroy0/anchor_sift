OPENQASM 2.0;
include "qelib1.inc";
// Bernstein-Vazirani over 12 bits with the secret 101101001101 (c[11] first): the one outcome is the secret
qreg q[12];
qreg a[1];
creg c[12];
x a[0];
h q;
h a[0];
cx q[0],a[0];
cx q[2],a[0];
cx q[3],a[0];
cx q[6],a[0];
cx q[8],a[0];
cx q[9],a[0];
cx q[11],a[0];
h q;
barrier q, a;
measure q -> c;
