-- Run this as:
--
-- sqlite3 -list path/to/database < sqlite-schema-diagram.sql > schema.dot
--
-- ...then render the schema.dot file to an image using your favourite
-- GraphViz tool.  I like using "xdot" for interactive use.
--
-- Note the "-list" option! This is important, it makes sure the
-- command-line tool doesn't get any of its own formatting in the
-- GraphViz output.

-- We start a GraphViz graph
SELECT '
digraph structs {
'
UNION ALL


-- By default, nodes have circles around them.  We will draw our own
-- tables below, we do not want the circles.
SELECT '
node [shape=none]
'
UNION ALL

-- This is the big query that renders a node complete with field names
-- for each table in the database.  Because we want raw GraphViz output,
-- our query returns rows with a single string field, whose value is a
-- complex calculation using SQL as a templating engine.  This is kind
-- of an abuse, but works nicely nevertheless.
SELECT
    CASE
        -- When the previous row's table name is the same as this one,
        -- do nothing.
        WHEN LAG(t.name, 1) OVER (ORDER BY t.name) = t.name THEN ''

        -- Otherwise, this is the first row of a new table, so start
        -- the node markup and add a header row.  Normally in GraphViz,
        -- the table name would *be* the label of the node, but since
        -- we're using the label to represent the entire node, we have
        -- to make our own header.
        --
        -- GraphViz does have a "record" label shape, but it seems tricky
        -- to work with and I found the HTML-style label markup easier
        -- to get working the way I wanted.
        ELSE
            t.name || ' [label=<
            <TABLE BORDER="0" CELLSPACING="0" CELLBORDER="1">
                <TR>
                    <TD COLSPAN="2"><B>' || t.name || '</B></TD>
                </TR>
            '

    -- After the header (if needed), we have rows for each field in
    -- the table.
    --
    -- The "pk" metadata field is zero for table fields that are not part
    -- of the primary key.  If the "pk" metadata field is 1 or more, that
    -- tells you that table field's order in the (potentially composite)
    -- primary key.
    --
    -- We also add ports to each of the table cells.  GraphViz's normal
    -- approach is to draw graph edges from the centre of one node to the
    -- centre of another, then draw the arrow head at the place where
    -- the line pierces the node's outline.  Here, our field names are
    -- packed closely together in a table, so GraphViz's approach gets
    -- very messy very quickly.  Being able to constrain edges to be
    -- drawn at the left and right sides of the table, and have incoming
    -- edges always on the left and outgoing edges always on the right,
    -- really helps keep things tidy.
    END || '
                <TR>
                    <TD PORT="' || i.name || '_to">' ||
                        CASE i.pk WHEN 0 THEN '&nbsp;' ELSE '🔑' END ||
                    '</TD>
                    <TD PORT="' || i.name || '_from">' || i.name || '</TD>
                </TR>
            ' ||
    CASE
        -- When the next row's table name is the same as this one,
        -- do nothing.
        WHEN LEAD(t.name, 1) OVER (ORDER BY t.name) = t.name THEN ''

        -- Otherwise, this is the last row of a database table, so end
        -- the table markup.
        ELSE '
            </TABLE>
        >];
        '
    END

-- This is how you get nice relational data out of SQLite's metadata
-- pragmas.
FROM pragma_table_list() AS t
    JOIN pragma_table_info(t.name, t.schema) AS i

WHERE
    -- SQLite has a bunch of metadata tables in each schema, which
    -- are hidden from .tables and .schema but which are reported
    -- in pragma_table_list().  They're not user-created and almost
    -- certainly user databases don't have foreign keys to them, so
    -- let's just filter them out.
    t.name NOT LIKE 'sqlite_%'

    -- Despite its name, pragma_table_list() also includes views.
    -- Since those don't store any information or have any correctness
    -- constraints, they're just distracting if you're trying to quickly
    -- understand a database's schema, so we'll filter them out too.
    AND t.type = 'table'
UNION ALL

-- Now we have all the database tables set up, we can draw the links
-- between them.  SQLite gives us the pragma_foreign_key_list() function
-- which (for a given source table) gives us all the information we need
-- to know.  We just do a bit more string concatenation to build up the
-- GraphViz syntax equivalent.
--
-- Note that we use the ports we defined above, as well as the directional
-- overrides :e and :w, to force GraphViz to give us a layout that's
-- likely to be readable.
SELECT
    t.name || ':' || f."from" || '_from:e -> ' ||
    f."table" || ':' || f."to" || '_to:w'
FROM pragma_table_list() AS t
    JOIN pragma_foreign_key_list(t.name, t.schema) AS f
UNION ALL

-- Lastly, we close the GraphViz graph.
SELECT '
}';
