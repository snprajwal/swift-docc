/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

extension RenderNode {
    public var headings: [String] {
        return contentSections
            // Exclude headings from call-to-action sections, since they always link to standalone (indexed) pages.
            .filter { $0.kind != .callToAction }
            .flatMap { $0.headings }
    }

    var rawIndexableTextContent: String {
        return contentSections
            // Exclude text from call-to-action sections, since they always link to standalone (indexed) pages.
            .filter { $0.kind != .callToAction }
            .map { $0.rawIndexableTextContent(references: references) }.joined(separator: " ")
    }
    
    private var contentSections: [any RenderSection] {
        guard kind == .symbol || (kind == .article && sections.isEmpty) else {
            return sections
        }
        
        return [ContentRenderSection(kind: .content, content: [.paragraph(.init(inlineContent: abstract ?? []))])]
            + primaryContentSections
    }
}

extension RenderNode: Indexable {
    func topLevelIndexingRecord(problems: inout [Problem]) -> IndexingRecord? {
        let kind: IndexingRecord.Kind
        switch self.kind {
        case .tutorial:
            kind = .tutorial
        case .section:
            kind = .tutorialSection
        case .overview:
            kind = .overview
        case .article:
            kind = .article
        case .symbol:
            kind = .symbol
        }
        
        guard let title = metadata.title, !title.isEmpty else {
            // Nodes without a title are erroneous entries in the symbol graph.
            // A search result cannot be constructed without a title, meaning that
            // an indexing record for this node is useless. The node is skipped.
            problems.append(Problem(diagnostic: Diagnostic(
                severity: .warning,
                identifier: "org.swift.docc.RenderNodeWithoutTitle",
                summary: "\(identifier.absoluteString.singleQuoted) has an empty title, and cannot have a usable search result"
            )))
            return nil
        }
        
        let summaryParagraph: RenderBlockContent?
        if let abstract = self.abstract {
            summaryParagraph = RenderBlockContent.paragraph(.init(inlineContent: abstract))
        } else if let intro = self.sections.first as? IntroRenderSection, let firstBlock = intro.content.first, case .paragraph = firstBlock {
            summaryParagraph = firstBlock
        } else {
            summaryParagraph = nil
        }

        let summary = summaryParagraph?.rawIndexableTextContent(references: references) ?? ""
        
        return IndexingRecord(kind: kind, location: .topLevelPage(identifier), title: title, summary: summary, headings: self.headings, rawIndexableTextContent: self.rawIndexableTextContent, platforms: metadata.platforms)
    }
    
    @available(*, deprecated, message: "This method will be removed in Swift 6.4, use ``RenderNode.indexingRecords(onPage:problems:)`` instead")
    public func indexingRecords(onPage page: ResolvedTopicReference) throws -> [IndexingRecord] {
        var problems = [Problem]()
        let records = indexingRecords(onPage: page, problems: &problems)
        // A call to ``RenderNode.indexingRecords(onPage:)`` can have exactly one possible problem,
        // which is that the node does not have a title to use for a search result. For backwards
        // compatibility, we throw the original error type if the `problems` array is non-nil.
        if !problems.isEmpty {
            throw IndexingError.missingTitle(page)
        }

        return records
    }

    public func indexingRecords(onPage page: ResolvedTopicReference, problems: inout [Problem]) -> [IndexingRecord] {
        switch self.kind {
        case .tutorial:
            let sectionRecords = self.sections
                .flatMap { section -> [IndexingRecord] in
                    guard let sectionsSection = section as? TutorialSectionsRenderSection else {
                        return []
                    }
                    return sectionsSection.indexingRecords(onPage: page, references: references)
            }
            
            return [topLevelIndexingRecord(problems: &problems)].compactMap({ $0 }) + sectionRecords
        default:
            return [topLevelIndexingRecord(problems: &problems)].compactMap({ $0 })
        }
    }
}
