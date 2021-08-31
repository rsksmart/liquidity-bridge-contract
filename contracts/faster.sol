// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

contract Slice {
      bytes memory a = hex"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f40414242434445464748494a4b4c4d4e4f";
    
  function test1()  external pure returns (uint32) {
      return getBtcBlockTimestamp(a);
  }
  
  function test2()  external pure returns (uint32) {
      return sliceUint32FromLSB(a,68);
  }

    
  function getBtcBlockTimestamp(bytes memory header) private pure returns (uint32) {
        // bitcoin header is 80 bytes and timestamp is 4 bytes from byte 68 to byte 71 (both inclusive) 
		// SDL: With some slicing you can avoid the shifts and use 
		// a lot less gas (2943 compared to 571)
        return (uint32)(shiftLeft(header[68], 24) | shiftLeft(header[69], 16) | shiftLeft(header[70], 8) | shiftLeft(header[71], 0));
    }


	// SDL: bytes must have at least 28 bytes before the uint32
	function sliceUint32FromLSB(bytes memory bs, uint start)
    internal pure
    returns (uint32)
	{
		require(bs.length >= start + 4, "slicing out of range");
		require(bs.length >= 32, "slicing out of range");
		start -=28;
		uint x;
		assembly {
			x := mload(add(bs, add(0x20, start)))
		}
		return uint32(x);
		//return (uint32) (x & (1<<32-1));
	}

    /**
        @dev Performs a left shift of a byte
        @param b The byte
        @param nBits The number of bits to shift
        @return The shifted byte
     */
    function shiftLeft(bytes1 b, uint nBits) private pure returns (bytes32){
        return (bytes32)(uint8(b) * 2 ** nBits);
    }
}
