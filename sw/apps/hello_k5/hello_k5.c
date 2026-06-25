#include <k5_libs.h> // Should be include in any application , takes care of all other rrequired includes.

int main() {
 
  // Notice bm_* functions, are some useful K5 available 'bare-metal' (i.e. no operating system) library functions. 

  // Print Greetings Message , bm_printf has sane format and arguments as C standard printf.
  bm_printf("HELLO K5, LETS GO\n");

  // Open a text file in read-mode, located st the  app source folder
  // You can view the text file at $MY_K5_PROJ/sw/apps/hello_k5/k5_example_in.txt
  int inF = bm_fopen_r("app_src_dir/k5_example_in.txt"); 
  
  char in_str [80] ;  // String Vector
  
  // Get next string from the source file. 
  // strings are separated on the text file by spaces and lines breaks.
  bm_fscans(inF,in_str) ;      

  // Print the captured string.
  bm_printf("%s\n",in_str);   
  
  // Close th input text file.
  bm_fclose(inF); 
  
  // Quit the application
  bm_quit_app();     
  return 0; // main exit code.
  
}

//----------------------------------------------------------------------------------------------
