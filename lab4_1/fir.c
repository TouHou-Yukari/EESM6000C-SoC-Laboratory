#include "fir.h"

void __attribute__ ( ( section ( ".mprjram" ) ) ) initfir() {
	//initial your fir
	for (int i=0; i<N; i++) inputbuffer[i] = 0;
	for (int i=0; i<N; i++) outputsignal[i] = 0;
}

int* __attribute__ ( ( section ( ".mprjram" ) ) ) fir(){
	initfir();
	//write down your fir
	int sum;
	int getData;
	for (int i=0; i<N; i++) {
	    sum = 0;
		getData = inputsignal[i];
		inputbuffer[i] = getData;
		for (int j=0; j<i+1; j++) {
			sum += inputbuffer[i-j] * taps[j];
		}
		outputsignal[i] = sum;
	}
	
	return outputsignal;
}
		
