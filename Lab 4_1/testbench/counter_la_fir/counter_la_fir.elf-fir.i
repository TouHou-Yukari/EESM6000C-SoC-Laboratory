# 0 "fir.c"
# 1 "/home/ubuntu/lab-exmem_fir/testbench/counter_la_fir//"
# 0 "<built-in>"
# 0 "<command-line>"
# 1 "fir.c"
# 1 "fir.h" 1





int taps[11] = {0,-10,-9,23,56,63,56,23,-9,-10,0};
int inputbuffer[11];
int inputsignal[11] = {1,2,3,4,5,6,7,8,9,10,11};
int outputsignal[11];
# 2 "fir.c" 2

void __attribute__ ( ( section ( ".mprjram" ) ) ) initfir() {

 for(int i=0; i<11; i=i+1){
  inputbuffer[i] = 0;
  outputsignal[i] = 0;
 }
}

int* __attribute__ ( ( section ( ".mprjram" ) ) ) fir(){


 for(int idx = 0; idx < 11 ; idx ++){
  for(int i=11 -1; i > 0;i--){
   inputbuffer[i] = inputbuffer[i-1];
  }
  inputbuffer[0] = inputsignal[idx];
  for(int cnt = 0; cnt < 11; cnt ++){
   outputsignal[idx] += inputbuffer[cnt] * taps[cnt];
  }
 }

 return outputsignal;
}
