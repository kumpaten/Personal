import web3
import brownie
from brownie import *
from brownie.test import given, strategy
import pytest


operator = accounts.load("deployer-rinkeby", password = "password")
dummy = accounts.load("user-rinkeby", password = "password")

class TestClassFailuresAtBeginning:

    @pytest.fixture(scope = "class")
    def stock(self, Stock): 
        return operator.deploy(Stock, "someStock", "SST", "www.MyURL.ch", "jeremiah")
    
    def test_issue_calledbyNotOwner_revertsWithOwnable(self, stock):
        with brownie.reverts("Ownable: caller is not the owner"):
            stock.issue(10 , {"from": dummy})
    
    def test_transfer_failsBecauseNoBodyIsApproved(self, stock):
        with brownie.reverts("Receiver not identified"):
            stock.transfer(dummy, 10)
    
    def test_issueForContinuation(self, stock):
        stock.issue(5000)

    @pytest.mark.parametrize("acc", [operator, dummy, accounts.load("acc3", password = "password")]) 
    def test_transfer_failsBecauseNoBodyIsApproved(self, stock, acc):
        with brownie.reverts("Receiver not identified"):
            stock.transfer(acc, 10)
    
    @pytest.mark.parametrize("acc,ident", [(dummy, 0x9876543210987654), (accounts.load("acc3", password = "password"), 0x1234567890123456)]) 
    def test_transfer_andTransferShouldRevertWithCodeBecauseInsufficientBalance(self, stock, acc, ident):
          stock.setIdentity(acc, ident, {"from": operator})
          with brownie.reverts("0x54"):
            stock.transfer(acc, 5001)
    
    def test_transfer_shouldRevertBecauseItsPaused(self, stock):
        stock.pause()
        with brownie.reverts("0x42"):
            stock.transfer(dummy, 10)

    def test_callSnapshot_shouldFailBecauseNotOnwer(self, stock): #CHECK HASROLES FUNCTIONS BECAUSE ONLYOWNER
        with brownie.reverts("not authorized"):
            stock.scheduleSnapshot(3030303030, {"from": dummy})

class TestClassStock:
  
    @pytest.fixture(scope = "class")
    def stock(self, Stock): 
        return operator.deploy(Stock, "someStock", "SST", "www.MyURL.ch", "jeremiah")

    def test_totalSupply_shouldBeZero(self, stock):
        assert stock.totalSupply() == 0
    
    def test_owner_shouldBeOperator(self, stock):
        assert stock.owner() == operator

    def test_pauser_shouldbeOperator(self, stock):
        assert stock.hasPauserRole() == operator
    
    def test_snapshotter_shouldbeOperator(self, stock):
        assert stock.hasSnapshotRole() == operator
    
    def test_contactInformation_isCorrectAndReturnsList(self, stock):
        assert stock.getContactInformation() == ("jeremiah", "www.MyURL.ch")
    
    @given(amount=strategy('uint', max_value=100))
    def test_issue_correspondsCorrectly(self, stock, amount):
        stock.issue(amount)
        assert stock.balanceOf(operator) == amount
    

    
    





