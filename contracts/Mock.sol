pragma solidity ^0.7.4;

contract Mock {

    int private status;

    function set(int s) external {
        status = s;
    }

    function check() external view returns (int s){
        return status;
    }
}
