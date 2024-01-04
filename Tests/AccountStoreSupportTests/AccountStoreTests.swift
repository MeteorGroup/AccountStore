import XCTest
import AccountStore

struct TestUser: User {
    var id: String = "test"
}

struct TestCredential: Codable {
    var seed: Int = 0
}

class TestContext: AccountContext {
    required init(user: TestUser, credential: TestCredential) {
        
    }
    
    func active(context: AccountActivationContext) {
        
    }
    
    func handleUserUpdate(_ user: TestUser) {
        
    }
    
    func deactive() {
        
    }
    
    func handleDeletion() {
        
    }
    
    typealias User = TestUser
    typealias Credential = TestCredential
}

typealias ZaoAccountStore = AccountStore<TestUser, TestCredential, TestContext>
typealias ZaoAccount = ZaoAccountStore.AccountType

final class AccountStoreTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        let store = ZaoAccountStore(name: "default")
        print(store.accounts)
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
