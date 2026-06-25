
# Invoke by : python $DDP25_PROJ_SM_ENV_APPS/xmemcpy_ref/check_xmemcpy.py

#----------------------------------------------------------------------------------


def read_hex_file(file_path) :

  print('Reading hex file %s' % file_path)

  hexF = open(file_path,'r')  
  
  vals_list = []
  
  for line in hexF : 
    for hex_val_str in line.split() : 
       skip_till_eol = (hex_val_str[0]=='#')  # Skip comment lines detected
       if skip_till_eol :           
              break       
       vals_list.append(int(hex_val_str,16))
    if skip_till_eol :           
       continue       

   
  return vals_list 

 
#------------------------------------------------------------------------------------------------

def are_lists_identical(list1, list2) :

  #  This method pairs elements from both lists and checks if all corresponding elements are equal.
  return  all(x == y for x, y in zip(list1, list2))
 
#------------------------------------------------------------------------------------------------

# MAIN

in_vals_list  = read_hex_file('xmemcpy_test_in.txt')
out_vals_list = read_hex_file('xmemcpy_test_out.txt')

lists_are_identical = are_lists_identical(in_vals_list, out_vals_list) 

if lists_are_identical:
   print('\nGREAT! Test Passed, source and destination values are identical\n')
else:   
   print('\nERROR! Test Failed, source and destination values are not identical')
   print('Check data xmemcpy_test_out.txt vs. xmemcpy_test_in.txt\n');