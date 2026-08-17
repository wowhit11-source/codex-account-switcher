import Foundation

public actor EncryptedProfileStore {
    private let paths: SwitcherPaths
    private let vault: CryptoVault
    private let writer: AtomicFileWriter
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(paths: SwitcherPaths = SwitcherPaths(), vault: CryptoVault = CryptoVault()) {
        self.paths = paths
        self.vault = vault
        self.writer = AtomicFileWriter()
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func loadProfiles() throws -> [AccountProfile] {
        guard FileManager.default.fileExists(atPath: paths.profileMetadataFile.path) else { return [] }
        let data = try Data(contentsOf: paths.profileMetadataFile, options: .mappedIfSafe)
        return try decoder.decode([AccountProfile].self, from: data)
            .sorted { $0.createdAt < $1.createdAt }
    }

    @discardableResult
    public func save(profile: AccountProfile, secret: ProfileSecret) throws -> AccountProfile {
        try AuthCacheValidator.validate(secret.authCache)
        try prepareDirectories()
        var profiles = try loadProfiles()

        let secretData = try encoder.encode(secret)
        let encrypted = try vault.encrypt(secretData)
        try writer.write(encrypted, to: profileFile(for: profile.id))

        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        try saveMetadata(profiles)
        return profile
    }

    public func profile(matchingAccountEmail email: String) throws -> AccountProfile? {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty else { return nil }

        for profile in try loadProfiles() {
            guard
                let secret = try? secret(for: profile.id),
                let storedEmail = secret.accountEmail,
                storedEmail.caseInsensitiveCompare(normalizedEmail) == .orderedSame
            else { continue }
            return profile
        }
        return nil
    }

    public func secret(for profileID: UUID) throws -> ProfileSecret {
        let url = profileFile(for: profileID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SwitcherError.profileNotFound
        }
        let encrypted = try Data(contentsOf: url, options: .mappedIfSafe)
        let data = try vault.decrypt(encrypted)
        let secret = try decoder.decode(ProfileSecret.self, from: data)
        try AuthCacheValidator.validate(secret.authCache)
        return secret
    }

    public func updateCachedAuthentication(
        profileID: UUID,
        authCache: Data,
        identity: AccountIdentity
    ) throws {
        let profiles = try loadProfiles()
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else {
            throw SwitcherError.profileNotFound
        }
        var profile = profiles[index]
        profile.maskedEmail = Redactor.maskEmail(identity.email)
        profile.planType = identity.planType
        profile.lastValidatedAt = Date()
        let secret = ProfileSecret(authCache: authCache, accountEmail: identity.email, planType: identity.planType)
        _ = try save(profile: profile, secret: secret)
    }

    public func markActive(_ profileID: UUID, identity: AccountIdentity) throws {
        var profiles = try loadProfiles()
        guard profiles.contains(where: { $0.id == profileID }) else {
            throw SwitcherError.profileNotFound
        }
        for index in profiles.indices {
            profiles[index].isActive = profiles[index].id == profileID
            if profiles[index].id == profileID {
                profiles[index].maskedEmail = Redactor.maskEmail(identity.email)
                profiles[index].planType = identity.planType
                profiles[index].lastValidatedAt = Date()
            }
        }
        try saveMetadata(profiles)
    }

    public func clearActiveProfile() throws {
        var profiles = try loadProfiles()
        for index in profiles.indices {
            profiles[index].isActive = false
        }
        try saveMetadata(profiles)
    }

    public func rename(_ profileID: UUID, to name: String) throws {
        var profiles = try loadProfiles()
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else {
            throw SwitcherError.profileNotFound
        }
        profiles[index].displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try saveMetadata(profiles)
    }

    public func delete(_ profileID: UUID) throws {
        var profiles = try loadProfiles()
        profiles.removeAll { $0.id == profileID }
        try saveMetadata(profiles)
        let file = profileFile(for: profileID)
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }

    public func purgeAll() throws {
        if FileManager.default.fileExists(atPath: paths.applicationSupport.path) {
            try FileManager.default.removeItem(at: paths.applicationSupport)
        }
        try vault.deleteKey()
    }

    private func prepareDirectories() throws {
        try FileManager.default.createDirectory(
            at: paths.profilesDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private func saveMetadata(_ profiles: [AccountProfile]) throws {
        try prepareDirectories()
        try writer.write(try encoder.encode(profiles), to: paths.profileMetadataFile)
    }

    private func profileFile(for profileID: UUID) -> URL {
        paths.profilesDirectory.appending(path: "\(profileID.uuidString).casprofile")
    }
}
