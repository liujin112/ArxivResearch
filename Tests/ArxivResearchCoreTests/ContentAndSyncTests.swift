import Testing
import Foundation
@testable import ArxivResearchCore

@Suite("content extraction and sync clients")
struct ContentAndSyncTests {
    @Test("HTML converter preserves headings, paragraphs, links, and math blocks")
    func convertsHTMLToMarkdown() throws {
        let html = """
        <html><body><h1>Title</h1><p>We prove <span class="ltx_Math">\\(x^2\\)</span>.</p><a href="https://arxiv.org">arXiv</a></body></html>
        """

        let markdown = HTMLToMarkdownConverter().convert(html)

        #expect(markdown.contains("# Title"))
        #expect(markdown.contains("We prove \\(x^2\\)."))
        #expect(markdown.contains("[arXiv](https://arxiv.org)"))
    }

    @Test("Markdown renderer emits complete HTML with math support hook")
    func rendersMarkdownHTML() throws {
        let html = MarkdownHTMLRenderer().render("# Summary\n\n**Authors:** Ada\n\nSee [arXiv](https://arxiv.org) and `code`.\n\nEquation: \\(x^2\\)")

        #expect(html.contains("<!doctype html>"))
        #expect(html.contains("window.MathJax"))
        #expect(html.contains("tex-chtml.js"))
        #expect(html.contains("<h1>Summary</h1>"))
        #expect(html.contains("<strong>Authors:</strong> Ada"))
        #expect(html.contains(#"<a href="https://arxiv.org">arXiv</a>"#))
        #expect(html.contains("<code>code</code>"))
    }

    @Test("Markdown renderer keeps display math and common markdown blocks readable")
    func rendersReadableMarkdownBlocksAndDisplayMath() throws {
        let markdown = """
        # Deep Read

        Intro line with inline \\(x_i\\)
        continues in the same paragraph.

        \\[
        y = x + 1
        \\]

        - first **finding**
        - second item

        ```python
        print("ok")
        ```

        | 项目 | 内容 |
        |---|---|
        | 方法 | flow matching |
        """

        let html = MarkdownHTMLRenderer().render(markdown)

        #expect(html.contains(#"<article class="paper-markdown">"#))
        #expect(html.contains("<p>Intro line with inline \\(x_i\\)\ncontinues in the same paragraph.</p>"))
        #expect(html.contains(#"<div class="math-display">"#))
        #expect(html.contains("\\[\ny = x + 1\n\\]"))
        #expect(html.contains("<p>\\[</p>") == false)
        #expect(html.contains("<ul>"))
        #expect(html.contains("<li>first <strong>finding</strong></li>"))
        #expect(html.contains(#"<pre><code class="language-python">print(&quot;ok&quot;)"#))
        #expect(html.contains("<table>"))
        #expect(html.contains("<th>项目</th>"))
        #expect(html.contains("<td>flow matching</td>"))
    }

    @Test("Notion create database request uses latest version and data source schema")
    func buildsNotionCreateDatabaseRequest() throws {
        let config = NotionConfig(tokenRef: "notion", parentPageID: "page-123", databaseID: nil, dataSourceID: nil)
        let request = try NotionAPIClient(config: config).buildCreateDatabaseRequest()

        #expect(request.url?.absoluteString == "https://api.notion.com/v1/databases")
        #expect(request.value(forHTTPHeaderField: "Notion-Version") == "2026-03-11")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer notion")
        #expect(String(data: request.httpBody ?? Data(), encoding: .utf8)?.contains("initial_data_source") == true)
        #expect(String(data: request.httpBody ?? Data(), encoding: .utf8)?.contains(#""is_inline":true"#) == true)
    }

    @Test("Notion ensure properties request patches an existing data source schema")
    func buildsNotionEnsurePropertiesRequest() throws {
        let config = NotionConfig(tokenRef: "notion", parentPageID: "page-123", databaseID: "db-123", dataSourceID: "ds-123")
        let request = try NotionAPIClient(config: config).buildEnsurePaperPropertiesRequest()
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""

        #expect(request.url?.absoluteString == "https://api.notion.com/v1/data_sources/ds-123")
        #expect(request.httpMethod == "PATCH")
        #expect(request.value(forHTTPHeaderField: "Notion-Version") == "2026-03-11")
        #expect(body.contains(#""properties""#))
        #expect(body.contains(#""Abstract""#))
        #expect(body.contains(#""Summary""#))
        #expect(body.contains(#""Deep Read Status""#))
    }

    @Test("Notion update page request patches the paper entry page")
    func buildsNotionUpdatePageRequest() throws {
        let config = NotionConfig(tokenRef: "notion", parentPageID: "page-123", databaseID: "db-123", dataSourceID: "ds-123")
        let request = try NotionAPIClient(config: config).buildUpdatePageRequest(
            pageID: "paper-page-123",
            paper: .fixture(arxivID: "2401.99999"),
            analysis: .fixture(tags: ["llm"]),
            deepRead: DeepReadReport(paperID: "2401.99999", prompt: "Prompt", markdown: "Deep read", sourceKind: .html)
        )
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""

        #expect(request.url?.absoluteString == "https://api.notion.com/v1/pages/paper-page-123")
        #expect(request.httpMethod == "PATCH")
        #expect(body.contains("Deep Read Status"))
        #expect(body.contains("ready"))
    }

    @Test("Notion append content request targets the paper entry page")
    func buildsNotionAppendContentRequest() throws {
        let config = NotionConfig(tokenRef: "notion", parentPageID: "page-123", databaseID: "db-123", dataSourceID: "ds-123")
        let request = try NotionAPIClient(config: config).buildAppendPageContentRequest(
            pageID: "paper-page-123",
            paper: .fixture(arxivID: "2401.99999"),
            analysis: .fixture(tags: ["llm"]),
            deepRead: DeepReadReport(paperID: "2401.99999", prompt: "Prompt", markdown: "Deep read", sourceKind: .html)
        )
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""

        #expect(request.url?.absoluteString == "https://api.notion.com/v1/blocks/paper-page-123/children")
        #expect(request.httpMethod == "PATCH")
        #expect(body.contains("Deep Read"))
    }

    @Test("Notion stores paper metadata in properties instead of page body")
    func notionMetadataStaysInPageProperties() throws {
        let config = NotionConfig(tokenRef: "notion", parentPageID: "page-123", databaseID: "db-123", dataSourceID: "ds-123")
        let paper = Paper.fixture(arxivID: "2401.99999")
        let request = try NotionAPIClient(config: config).buildCreatePageRequest(
            paper: paper,
            analysis: .fixture(tags: ["llm", "agents"]),
            deepRead: DeepReadReport(paperID: "2401.99999", prompt: "Prompt", markdown: "Deep read", sourceKind: .html)
        )
        let body = try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        let properties = try #require(body["properties"] as? [String: Any])
        let children = try #require(body["children"] as? [[String: Any]])
        let childrenJSON = String(data: try JSONSerialization.data(withJSONObject: children), encoding: .utf8) ?? ""

        #expect(properties["Abstract"] != nil)
        #expect(properties["Summary"] != nil)
        #expect(properties["Tags"] != nil)
        #expect(childrenJSON.contains("A compact abstract for testing.") == false)
        #expect(childrenJSON.contains("This paper is useful for testing.") == false)
        #expect(childrenJSON.contains("Tags:") == false)
        #expect(childrenJSON.contains("llm") == false)
    }

    @Test("Notion deep read content preserves display and inline formulas")
    func notionDeepReadPreservesFormulas() throws {
        let config = NotionConfig(tokenRef: "notion", parentPageID: "page-123", databaseID: "db-123", dataSourceID: "ds-123")
        let request = try NotionAPIClient(config: config).buildAppendPageContentRequest(
            pageID: "paper-page-123",
            paper: .fixture(arxivID: "2401.99999"),
            analysis: nil,
            deepRead: DeepReadReport(
                paperID: "2401.99999",
                prompt: "Prompt",
                markdown: "Inline formula \\(x^2\\).\n\n\\[\ny=x+1\n\\]\n\nDone.",
                sourceKind: .html
            )
        )
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""

        #expect(body.contains(#""type":"equation""#))
        #expect(body.contains(#""expression":"x^2""#))
        #expect(body.contains(#""expression":"y=x+1""#))
    }

    @Test("Notion deep read markdown renders structured blocks")
    func notionDeepReadRendersStructuredMarkdownBlocks() throws {
        let config = NotionConfig(tokenRef: "notion", parentPageID: "page-123", databaseID: "db-123", dataSourceID: "ds-123")
        let request = try NotionAPIClient(config: config).buildAppendPageContentRequest(
            pageID: "paper-page-123",
            paper: .fixture(arxivID: "2401.99999"),
            analysis: nil,
            deepRead: DeepReadReport(
                paperID: "2401.99999",
                prompt: "Prompt",
                markdown: """
                ## 方法概览

                Inline formula $x^2$ remains readable.

                $$
                y = x + 1
                $$

                - first **finding**
                - second item

                ```python
                print("ok")
                ```

                | 项目 | 内容 |
                |---|---|
                | 方法 | flow \\| matching |
                """,
                sourceKind: .html
            )
        )
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""

        #expect(body.contains(#""type":"heading_2""#))
        #expect(body.contains(#""type":"bulleted_list_item""#))
        #expect(body.contains(#""type":"code""#))
        #expect(body.contains(#""language":"python""#))
        #expect(body.contains(#""type":"table""#))
        #expect(body.contains(#""type":"table_row""#))
        #expect(body.contains(#""expression":"x^2""#))
        #expect(body.contains(#""expression":"y = x + 1""#))
        #expect(body.contains("flow | matching"))
    }

    @Test("Notion create database response parser keeps database and data source IDs")
    func parsesNotionCreateDatabaseResponse() throws {
        let data = Data("""
        {
          "object": "database",
          "id": "db-123",
          "data_sources": [
            { "object": "data_source", "id": "ds-123" }
          ]
        }
        """.utf8)

        let parsed = NotionResponseParser.createdDatabase(from: data)

        #expect(parsed?.databaseID == "db-123")
        #expect(parsed?.dataSourceID == "ds-123")
    }

    @Test("Notion create page response parser keeps paper page ID")
    func parsesNotionPageID() throws {
        let data = Data(#"{"object":"page","id":"paper-page-123"}"#.utf8)

        #expect(NotionResponseParser.createdPageID(from: data) == "paper-page-123")
    }

    @Test("Zotero create item request targets selected library and collection")
    func buildsZoteroCreateItemRequest() throws {
        let config = ZoteroConfig(tokenRef: "zotero", library: .user(id: 123), collectionKey: "COLL123")
        let paper = Paper.fixture(arxivID: "2401.00001")
        let analysis = LLMAnalysis.fixture(tags: ["llm", "retrieval"])

        let request = try ZoteroAPIClient(config: config).buildCreateItemRequest(paper: paper, analysis: analysis)

        #expect(request.url?.absoluteString == "https://api.zotero.org/users/123/items")
        #expect(request.value(forHTTPHeaderField: "Zotero-API-Key") == "zotero")
        #expect(String(data: request.httpBody ?? Data(), encoding: .utf8)?.contains("COLL123") == true)
        #expect(String(data: request.httpBody ?? Data(), encoding: .utf8)?.contains("arXiv: 2401.00001") == true)
    }
}
