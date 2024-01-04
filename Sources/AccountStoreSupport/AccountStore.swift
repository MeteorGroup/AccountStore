//
//  AccountStore.swift
//
//  Created by Yu Ao on 2019/12/13.
//  Copyright © 2019 Yu Ao. All rights reserved.
//

import Foundation

public protocol AccountUser: Codable {
    var id: String { get }
}

public protocol AccountContext: class {
    associatedtype User
    associatedtype Credential
    
    init(user: User, credential: Credential)
    
    func active(context: AccountActivationContext)
    
    func handleUserUpdate(_ user: User)
    
    func deactive()
    
    func handleDeletion()
}

public struct Account<U, C, Context> where U: AccountUser, C: Codable, Context: AccountContext, Context.User == U, Context.Credential == C {
    
    public private(set) var credential: C
    public private(set) var identifier: String
    public private(set) var user: U
    
    public let context: Context
    
    public init(user: U, credential: C) {
        self.user = user
        self.identifier = user.id
        self.credential = credential
        self.context = Context(user: user, credential: credential)
    }
    
    public mutating func update(user: U) {
        assert(user.id == self.identifier)
        self.user = user
        self.context.handleUserUpdate(user)
    }
}

extension Account: Codable {
    internal enum CodingKeys: CodingKey {
        case user
        case identifier
        case credential
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.user = try container.decode(U.self, forKey: .user)
        self.identifier = try container.decode(String.self, forKey: .identifier)
        let credentialInfo = try container.decode(Data.self, forKey: .credential)
        if let credentialStore = decoder.userInfo[AccountCodingUserInfoKey.credentialStore] as? CredentialStore {
            let data = try credentialStore.loadCredentialData(forAccount: self.identifier, info: credentialInfo)
            self.credential = try PropertyListDecoder().decode(C.self, from: data)
        } else {
            fatalError()
        }
        self.context = Context(user: user, credential: credential)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.identifier, forKey: .identifier)
        try container.encode(self.user, forKey: .user)
        let credentialData = try PropertyListEncoder().encode(self.credential)
        if let credentialStore = encoder.userInfo[AccountCodingUserInfoKey.credentialStore] as? CredentialStore {
            let data = try credentialStore.storeCredentialData(credentialData, forAccount: self.identifier)
            try container.encode(data, forKey: .credential)
        } else {
            fatalError()
        }
    }
}

internal struct AccountCodingUserInfoKey {
    static let credentialStore: CodingUserInfoKey = CodingUserInfoKey(rawValue: "AccountCodingUserInfoKey.CredentialStore")!
}

public protocol CredentialStore {
    //Stores the credential data and returns an optional data object with additional info, for example, AES-iv.
    func storeCredentialData(_ data: Data, forAccount identifier: String) throws -> Data
    
    //Loads the credential data with saved info.
    func loadCredentialData(forAccount identifier: String, info: Data) throws -> Data
    
    func deleteCredentialData(forAccount identifier: String)
}

public class DefaultCredentialStore: CredentialStore {
    public func storeCredentialData(_ data: Data, forAccount identifier: String) throws -> Data {
        return data
    }
    
    public func loadCredentialData(forAccount identifier: String, info: Data) throws -> Data {
        return info
    }
    
    public func deleteCredentialData(forAccount identifier: String) {
        
    }
    
    public init() {}
}

public enum AccountActivationContext {
    case normal
    case register
    case login
}

public class AccountStore<U, C, Context> where U: AccountUser, C: Codable, Context: AccountContext, Context.User == U, Context.Credential == C {
    
    public typealias AccountType = Account<U, C, Context>
    
    public var currentAccount: AccountType? {
        return self.accounts.last
    }
    
    public init(name: String, directory: FileManager.SearchPathDirectory = .applicationSupportDirectory, credentialStore: CredentialStore = DefaultCredentialStore()) {
        let fileManager = FileManager()
        let url = (try! fileManager.url(for: directory, in: .userDomainMask, appropriateFor: nil, create: true)).appendingPathComponent("com.meteor.account-store-\(name).data")
        self.url = url
        self.credentialStore = credentialStore
        if fileManager.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                let decoder = PropertyListDecoder()
                decoder.userInfo = [AccountCodingUserInfoKey.credentialStore: self.credentialStore]
                self.accounts = try decoder.decode([AccountType].self, from: data)
            } catch {
                assertionFailure(error.localizedDescription)
                self.accounts = []
            }
        } else {
            self.accounts = []
        }
        
        var urlForSettingResourceValues = url
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? urlForSettingResourceValues.setResourceValues(resourceValues)
        
        self.currentAccount?.context.active(context: .normal)
    }
    
    public func register(_ account: AccountType) {
        guard !self.accounts.contains(where: { $0.identifier == account.identifier }) else {
            assertionFailure()
            return
        }
        self.currentAccount?.context.deactive()
        self.accounts.append(account)
        account.context.active(context: .register)
    }
    
    public func login(_ account: AccountType) {
        guard !self.accounts.contains(where: { $0.identifier == account.identifier }) else {
            assertionFailure()
            return
        }
        self.currentAccount?.context.deactive()
        self.accounts.append(account)
        account.context.active(context: .login)
    }
    
    public func active(_ account: AccountType) {
        if let accountIndex = self.accounts.firstIndex(where: { $0.identifier == account.identifier }) {
            if self.currentAccount?.identifier == account.identifier {
                self.accounts[accountIndex] = account
            } else {
                self.currentAccount?.context.deactive()
                self.accounts.remove(at: accountIndex)
                self.accounts.append(account)
                account.context.active(context: .normal)
            }
        } else {
            assertionFailure()
        }
    }
    
    public func removeAccount(with identifier: String) {
        guard let accountIndex = self.accounts.firstIndex(where: { $0.identifier == identifier }) else {
            assertionFailure()
            return
        }
        
        let currentID = self.currentAccount?.identifier
        
        let account = self.accounts[accountIndex]
        
        if account.identifier == currentID {
            account.context.deactive()
        }
        
        account.context.handleDeletion()
        self.accounts.remove(at: accountIndex)
        self.credentialStore.deleteCredentialData(forAccount: account.identifier)
        
        if self.currentAccount?.identifier != currentID {
            self.currentAccount?.context.active(context: .normal)
        }
    }
    
    public func removeAccounts(where shouldRemove: (AccountType) -> Bool) {
        let currentID = self.currentAccount?.identifier
        
        var ids: [String] = []
        for account in self.accounts {
            if shouldRemove(account) {
                ids.append(account.identifier)
            }
        }
        for id in ids {
            guard let accountIndex = self.accounts.firstIndex(where: { $0.identifier == id }) else {
                assertionFailure()
                return
            }
            let account = self.accounts[accountIndex]
            if account.identifier == currentID {
                account.context.deactive()
            }
            account.context.handleDeletion()
            self.accounts.remove(at: accountIndex)
            self.credentialStore.deleteCredentialData(forAccount: account.identifier)
        }
        
        if self.currentAccount?.identifier != currentID {
            self.currentAccount?.context.active(context: .normal)
        }
    }
    
    public func update(user: U) {
        guard let accountIndex = self.accounts.firstIndex(where: { $0.identifier == user.id }) else {
            assertionFailure()
            return
        }
        self.accounts[accountIndex].update(user: user)
    }
    
    public private(set) var accounts: [AccountType] {
        didSet {
            do {
                let encoder = PropertyListEncoder()
                encoder.userInfo = [AccountCodingUserInfoKey.credentialStore: self.credentialStore]
                let data = try encoder.encode(self.accounts)
                try data.write(to: self.url, options: .atomic)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }
    
    private let credentialStore: CredentialStore
    
    private let url: URL
}

