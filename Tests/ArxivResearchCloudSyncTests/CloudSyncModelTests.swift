import Foundation
import Testing
@testable import ArxivResearchCore
@testable import ArxivResearchCloudSync

@Suite("Cloud sync record models")
struct CloudSyncModelTests {
    @Test("Record names are stable and CloudKit safe")
    func recordNamesAreStableAndSafe() {
        #expect(CloudSyncRecordName.paper("2606.12213").rawValue == "paper_2606_12213")
        #expect(CloudSyncRecordName.job(idempotencyKey: "summarizeAbstract:2606.12213").rawValue == "job_summarizeAbstract_2606_12213")
    }

    @Test("Paper records round trip core paper fields")
    func paperRecordsRoundTripCoreFields() throws {
        var paper = Paper.fixture(arxivID: "2606.12213")
        paper.tags = ["style-transfer", "panorama-generation"]
        paper.status = .summarized
        let metadata = SyncMetadata(
            updatedAt: Date(timeIntervalSince1970: 1_781_000_000),
            originDeviceID: "ios-a",
            revision: 3
        )

        let record = CloudPaperRecord(paper: paper, metadata: metadata)
        let restored = record.paper()

        #expect(record.recordName == CloudSyncRecordName.paper("2606.12213").rawValue)
        #expect(record.metadata == metadata)
        #expect(restored.arxivID == paper.arxivID)
        #expect(restored.title == paper.title)
        #expect(restored.tags == paper.tags)
        #expect(restored.status == .summarized)
        #expect(restored.pdfURL == paper.pdfURL)
    }

    @Test("Job records preserve typed payload and idempotency")
    func jobRecordsPreserveTypedPayloadAndIdempotency() throws {
        let job = try SyncJob.paperJob(
            kind: .deepRead,
            paperID: "2606.12213",
            originDeviceID: "ios-a"
        )

        let record = try CloudJobRecord(job: job)
        let restored = try record.job()

        #expect(record.recordName == "job_deepRead_2606_12213")
        #expect(record.typedPayload == .paper(id: "2606.12213"))
        #expect(restored.kind == .deepRead)
        #expect(restored.idempotencyKey == "deepRead:2606.12213")
        #expect(restored.originDeviceID == "ios-a")
        #expect(try restored.typedPayload() == .paper(id: "2606.12213"))
    }

    @Test("Duplicate job idempotency keys map to the same cloud record")
    func duplicateJobIdempotencyKeysMapToSameRecord() throws {
        let first = try SyncJob.paperJob(kind: .summarizeAbstract, paperID: "2606.12213")
        let second = try SyncJob.paperJob(kind: .summarizeAbstract, paperID: "2606.12213")

        let firstName = try CloudJobRecord(job: first).recordName
        let secondName = try CloudJobRecord(job: second).recordName
        #expect(firstName == secondName)
    }

    @Test("Lease policy allows pending and stale running jobs only")
    func leasePolicyAllowsPendingAndStaleRunningJobsOnly() {
        let now = Date(timeIntervalSince1970: 2_000)
        let policy = CloudJobLeasePolicy(staleAfter: 600)
        let pending = CloudJobRecord(
            recordName: "job_pending",
            jobID: UUID(),
            kind: .summarizeAbstract,
            state: .pending,
            typedPayload: .paper(id: "2606.12213"),
            attempts: 0,
            scheduledAt: now,
            lastError: nil,
            idempotencyKey: "summarizeAbstract:2606.12213",
            originDeviceID: "ios-a",
            claimedByDeviceID: nil,
            claimedAt: nil,
            completedAt: nil
        )
        var freshRunning = pending
        freshRunning.state = .running
        freshRunning.claimedAt = now.addingTimeInterval(-100)
        var staleRunning = freshRunning
        staleRunning.claimedAt = now.addingTimeInterval(-601)
        var succeeded = pending
        succeeded.state = .succeeded

        #expect(policy.canClaim(pending, by: "mac-a", now: now))
        #expect(policy.canClaim(freshRunning, by: "mac-a", now: now) == false)
        #expect(policy.canClaim(staleRunning, by: "mac-a", now: now))
        #expect(policy.canClaim(succeeded, by: "mac-a", now: now) == false)
    }
}
