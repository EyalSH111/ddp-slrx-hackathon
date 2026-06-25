import numpy as np
import random

#--------------------------------------------------------------------------------------

# Little endian and hex print assistance functions

# signed int
def int32_ltlend_hex_str(val):
    val = (val + (1 << 32)) % (1 << 32)
    bigend_hex_str = '%08x' % val
    ltlend_hex_str = '%s %s %s %s ' % (bigend_hex_str[6:8],bigend_hex_str[4:6],bigend_hex_str[2:4],bigend_hex_str[0:2])
    return ltlend_hex_str 

# unsigned int
def uint32_ltlend_hex_str(val):
    bigend_hex_str = '%08x' % val
    ltlend_hex_str = '%s %s %s %s ' % (bigend_hex_str[6:8],bigend_hex_str[4:6],bigend_hex_str[2:4],bigend_hex_str[0:2])
    return ltlend_hex_str 

# signed char
def int8_hex_str(val): 
    val = (val + (1 << 8)) % (1 << 8)
    return '%02x' % val

#-------------------------------------------------------------------------------------

# Xbox hard configuration
XBOX_TCM_BASE_ADDR = 0x40000000
XMEM_SIZE = 2*1024*32  # size in bytes 

#-------------------------------------------------------------------------------------

# Generate random configuration

NUM_BYTES_LIMT = 3000

xmc_num_bytes       = random.randint(1,min(XMEM_SIZE//2,NUM_BYTES_LIMT))
xmem_rand_low_ofst  = random.randint(0,XMEM_SIZE-(2*xmc_num_bytes)) 
xmem_rand_high_ofst = random.randint(xmem_rand_low_ofst+xmc_num_bytes, XMEM_SIZE-xmc_num_bytes)

is_src_low_ofst  = random.choice([True, False])

if is_src_low_ofst :
  xmem_src_addr = XBOX_TCM_BASE_ADDR + xmem_rand_low_ofst
  xmem_dst_addr = XBOX_TCM_BASE_ADDR + xmem_rand_high_ofst   
else :    
  xmem_src_addr = XBOX_TCM_BASE_ADDR + xmem_rand_high_ofst
  xmem_dst_addr = XBOX_TCM_BASE_ADDR + xmem_rand_low_ofst  

# write configuration file

config_file = open('xmemcpy_test_config.txt','w')

config_file.write('# Notice ALL values are in hex bytes\n')
config_file.write('# Notice int words are provided in little endian (value least significant byte is first)\n\n')

config_file.write('%s # xmem_src_addr = %08x \n' % (uint32_ltlend_hex_str(xmem_src_addr), xmem_src_addr))
config_file.write('%s # xmem_dst_addr = %08x \n' % (uint32_ltlend_hex_str(xmem_dst_addr), xmem_dst_addr))
config_file.write('%s # xmc_num_bytes = %08x (%d decimal)\n' %  (uint32_ltlend_hex_str(xmc_num_bytes), xmc_num_bytes, xmc_num_bytes))   

config_file.close()

# Generate random data

test_data_vec = np.random.randint(0,255, size=(xmc_num_bytes)) 

test_in_file = open('xmemcpy_test_in.txt','w')

test_in_file.write('# Test input Data (unsigned hex bytes):\n\n')

num_bytes_per_input_line = 32
for i in range(xmc_num_bytes) : 
  test_in_file.write('%02x' % test_data_vec[i])
  i+=1
  if i%32==0 :
    test_in_file.write('\n')
  else :
    test_in_file.write(' ')

test_in_file.write('\n')
test_in_file.close()

