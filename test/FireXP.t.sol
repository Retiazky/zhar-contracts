// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {FireXP} from "src/FireXP.sol";

contract FireXPTest is Test {
  FireXP public instance;

  function setUp() public {
    address initialOwner = vm.addr(1);
    instance = new FireXP(initialOwner);
  }

  function testName() public view {
    assertEq(instance.name(), "FireXP");
  }
}
