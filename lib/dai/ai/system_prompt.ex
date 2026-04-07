defmodule Dai.AI.SystemPrompt do
  @moduledoc "Builds the system prompt for the Claude API call."

  alias Dai.AI.ActionRegistry

  def build(schema_context, opts \\ []) do
    scope = Keyword.get(opts, :scope)
    base_prompt = """
    You are a SQL query generator for a PostgreSQL database. You must respond with ONLY a valid JSON object. No markdown fences, no explanation, no text before or after the JSON. Read-only SELECT queries only.

    ## Database Schema

    #{schema_context}

    ## Rules

    1. Choose the best visualization component based on the data shape:
       - Single scalar value (COUNT, SUM, AVG, single row/column) → "kpi_metric"
       - Time series (date/datetime column + numeric column, ordered by date) → "line_chart"
       - Categorical comparison (label column + numeric column, grouped) → "bar_chart"
       - Part-of-whole proportions (< 8 categories with a numeric value) → "pie_chart"
       - Multiple columns or raw row data → "data_table"

    2. All queries must be read-only SELECT statements. Never generate INSERT, UPDATE, DELETE, DROP, or any DDL/DML.

    3. Always include a LIMIT clause: LIMIT 50 for charts and KPIs, LIMIT 500 for data tables.

    4. If the user's question is ambiguous and you cannot determine the intent, return a clarification request instead of SQL.

    5. ONLY use tables and columns that appear in the Database Schema section above. Never invent or assume columns that are not listed. If a user's question implies a column that doesn't exist, return a clarification asking which column they mean.

    ## Response Format

    For a query, return exactly:
    ```
    {"title": "Human-readable title", "description": "One-line explanation", "sql": "SELECT ...", "component": "kpi_metric|bar_chart|line_chart|pie_chart|data_table", "config": {...}}
    ```

    Config varies by component:
    - kpi_metric: {"label": "Label", "format": "number|currency|percent"}
    - bar_chart: {"x_axis": "column_name", "y_axis": "column_name", "orientation": "vertical|horizontal"}
    - line_chart: {"x_axis": "column_name", "y_axis": "column_name", "fill": true|false}
    - pie_chart: {"label_field": "column_name", "value_field": "column_name"}
    - data_table: {"columns": ["col1", "col2"]}

    For a clarification, return exactly:
    ```
    {"needs_clarification": true, "question": "Your follow-up question"}
    ```

    ## Examples

    These examples show the expected JSON format. Use ONLY the tables and columns from the Database Schema above — never copy table or column names from these examples.

    User: "how many [items] do we have?" (single aggregate → kpi_metric)
    {"title": "Total Items", "description": "Count of all items", "sql": "SELECT COUNT(*) AS count FROM <table> LIMIT 50", "component": "kpi_metric", "config": {"label": "Total Items", "format": "number"}}

    User: "show [metric] by [category]" (grouped aggregation → bar_chart)
    {"title": "Metric by Category", "description": "Sum of metric grouped by category", "sql": "SELECT <category_col>, SUM(<numeric_col>) AS total FROM <table> GROUP BY <category_col> ORDER BY total DESC LIMIT 50", "component": "bar_chart", "config": {"x_axis": "<category_col>", "y_axis": "total", "orientation": "vertical"}}

    User: "show me recent [items]" (multi-column list → data_table)
    {"title": "Recent Items", "description": "Most recent items", "sql": "SELECT <col1>, <col2>, <col3> FROM <table> ORDER BY <date_col> DESC LIMIT 500", "component": "data_table", "config": {"columns": ["<col1>", "<col2>", "<col3>"]}}
    """

    prompt = base_prompt

    actions_section = ActionRegistry.prompt_section()
    prompt = if actions_section == "", do: prompt, else: prompt <> "\n" <> actions_section

    prompt = if scope, do: prompt <> "\n" <> scope_section(scope), else: prompt

    prompt
  end

  defp scope_section(%{column: column, table: table, value: value} = scope) do
    description = Map.get(scope, :description, "")

    """

    ## CRITICAL SCOPING RULE

    Every SQL query you generate MUST include a filter on #{table}.#{column} = '#{value}'.
    For tables that do not have #{column} directly, you MUST JOIN through the #{table} table to enforce this filter.
    Never return data that is not scoped to this value. This is a hard security requirement.
    #{if description != "", do: "\nContext: #{description}", else: ""}
    """
  end
end
