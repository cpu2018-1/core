#include <stdio.h>
#include <stdlib.h>

int main(int argc,char** argv){
	FILE *fp;

	if(argc != 2){
		fprintf(stderr,"wrong args");
		return 1;
	}
	fp = fopen(argv[1],"rb");
	if(fp == NULL){
		fprintf(stderr,"fopen failed\n");
		return 1;
	}
	
	printf("memory_initialization_radix=16;\nmemory_initialization_vector=");
	
	int counter = 0;
	unsigned char c[4];
	while(1){
		int num = fread(c,1,4,fp);
		if(num != 4){
			if(num != 0 || feof(fp) != 0){
				fprintf(stderr,"wrong size of file");
			}
			break;
		}
		printf("\n");
		for(int i = 3; i >= 0; i--){
			unsigned int ui = (unsigned int)c[i];
			printf("%02x",ui);
		}
		counter++;
	}
	printf(";\n");
	fclose(fp);
	fprintf(stderr,"%d instr\n",counter);
	return 0;	
}
