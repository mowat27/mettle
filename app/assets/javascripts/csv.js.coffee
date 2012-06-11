root = global ? window

class root.MettleCsvReader
  valid_values = (row) ->
    delete row[""]
    row

  constructor: (csv_data, options) ->
    @headers = _($.csvIn.toArray(csv_data, options)[0]).filter (colname) -> colname != ""
    @rows    = (valid_values(row) for row in $.csvIn.toJSON(csv_data, options))

  is_valid_csv_file: ->
    true

  to_json: ->
    """
    {
      \"column_names\" : #{$.toJSON(@headers)},
      \"row_data\" : #{$.toJSON(@rows)}
    }
    """

if exports?
  exports.MettleCsvReader = root.MettleCsvReader

