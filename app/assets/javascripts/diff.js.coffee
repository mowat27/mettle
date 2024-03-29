root = global ? window
Hashtable = root.Hashtable

root.Diff = {}

root.intersection = (lhs_index, rhs_index, callbacks) ->
  return if !callbacks?

  my_callbacks = _.extend {
    on_match: -> null
    on_unmatched_lhs: -> null
    on_unmatched_rhs: -> null
  }, callbacks

  rhs_key_values = rhs_index.key_values()
  lhs_key_values = lhs_index.key_values()

  rhs_key_values.each (key_value) ->
    if !lhs_index.has_key(key_value)
      unmatched_rows = rhs_index.get(key_value)
      my_callbacks.on_unmatched_rhs(key_value, unmatched_rows)

  lhs_key_values.each (key_value) ->
    lhs_rows = lhs_index.get(key_value)
    rhs_rows = rhs_index.get(key_value)
    if rhs_rows.is_empty()
      my_callbacks.on_unmatched_lhs(key_value, lhs_rows)
    else
      my_callbacks.on_match(key_value, lhs_rows, rhs_rows)

root.cartesian = (lhs,rhs) ->
  result = []
  lhs.each (lhs_row) ->
    rhs.each (rhs_row) ->
      result.push([lhs_row, rhs_row])
  result

class root.Diff.Comparison
  constructor: (key) ->
    @key = key
    @expected =
      column_names: []
      data_set: new root.Diff.DataSet []
    @actual =
      column_names: []
      data_set: new root.Diff.DataSet []
    @json = '{"column_names": [], "results": []}'

  column_names: ->
    @array_intersection( @expected.column_names, @actual.column_names )

  load_data = (data, options, callbacks) ->
    try
      csv_reader = new root.MettleCsvReader(data, options)
      json = "#{csv_reader.to_json()}\n"
      callbacks.on_success.apply(self, [json])
    catch e
      callbacks.on_error(e)

  read_csv_files = (file_list, options, callbacks) ->
    self = this
    for file in file_list
      reader = new FileReader

      reader.onloadend = (evt) ->
        data = evt.target.result
        load_data(data, options, callbacks)

      reader.readAsText(file)


  load_results: (type, file_list, options, callbacks) ->
    target = @expected if type == "expected"
    target = @actual if type == "actual"

    options = options ? {}
    callbacks = callbacks ? {on_error: -> null}

    callbacks.on_start() if callbacks.on_start?

    read_csv_files file_list, options,
      on_error:
        callbacks.on_error
      on_success: (json) ->
        src = JSON.parse(json)
        target.column_names = src.column_names
        target.data_set = root.Diff.DataSet.create_from_json(json)
        callbacks.on_success() if callbacks.on_success?

  load_pasted_results: (type, data, options, callbacks) ->
    target = @expected if type == "expected"
    target = @actual if type == "actual"

    options = options ? {}
    callbacks = callbacks ? {on_error: -> null}

    callbacks.on_start() if callbacks.on_start?

    load_data data, options,
      on_error:
        callbacks.on_error
      on_success: (json) ->
        src = JSON.parse(json)
        target.column_names = src.column_names
        target.data_set = root.Diff.DataSet.create_from_json(json)
        callbacks.on_success() if callbacks.on_success?

  zip = (lhs, rhs, func) ->
    for i, lhs_item of lhs
      func(i, lhs_item, rhs[i])

  encode_result = (column_names, expected_row, actual_row) ->
    this_result = {}
    expected_row.zip actual_row, (colnum, e_val, a_val) ->
      column_name = column_names[colnum]
      this_result[column_name] =
        expected: e_val
        actual: a_val
    this_result

  join = (key, column_names, expected, actual) ->
    indexes =
      expected: new root.Diff.Index(key, column_names, expected)
      actual: new root.Diff.Index(key, column_names, actual)

    results = []
    intersection indexes.expected, indexes.actual,
      on_match: (key_value, expected_ds, actual_ds) ->
        _(cartesian(expected_ds, actual_ds)).each (product) ->
          [expected_row, actual_row] = product
          this_result = encode_result(column_names, expected_row, actual_row)
          results.push(this_result)
    results

  compare: ->
    @json = JSON.stringify
      column_names: @expected.column_names
      results: join(@key, @expected.column_names, @expected.data_set, @actual.data_set)

  to_json: ->
    @json

  array_intersection: (first_list, second_list) ->
    result = []

    for first_item in first_list
      for second_item in second_list
        if first_item == second_item
          result.push first_item

    @set(result)

  set: (list) ->
    result = []
    for item in list
      if result.indexOf item
        result.push item

    result


class root.Diff.DataSet
  is_row_array = (source) ->
    source[0]? && source[0].values?

  constructor: (source) ->
    if is_row_array(source)
      @rows = source
    else
      @rows = (new root.Diff.Row(values) for values in source)

  @create_from_json: (json) ->
    json_data = JSON.parse("#{json}")
    values = []
    for row_data in json_data.row_data
      this_row = []
      for column_name, value of row_data
        this_row.push(value)
      values.push(this_row)
    new root.Diff.DataSet(values)

  is_empty: ->
    @rows.length == 0

  slice: (column_names, key) ->
    result = (row.slice(column_names, key) for row in @rows)
    new root.Diff.DataSet(result)

  filter: (column_names, key, search_for) ->
    result = []
    for row in @rows
      key_values_for_this_row = row.slice(column_names, key)
      if key_values_for_this_row.equals(search_for)
        result.push(row)
    new root.Diff.DataSet result

  each: (func) ->
    for row in @rows
      func(row)

  each_row_with_index: (func) ->
    for index, row of @rows
      func(index, row)

  toString: ->
    result = "{root.Diff.DataSet rows = ["
    for row in @rows
      result += "#{row.toString()},"
    result.replace(/,*$/, "]}")

  equals: (other) ->
    return false unless other.rows
    return false if @rows.length != other.rows.length
    for i, row of @rows
      return false unless row.equals(other.rows[i])
    true

  isEqual: @equals


class root.Diff.Row
  constructor: (values) ->
    @values = []
    for value in values
      if typeof value isnt 'undefined'
        @values.push(value)
      else
        @values.push("")

  get: (column_names, name) ->
    i = column_names.indexOf(name)
    if i > -1
      @values[i]
    else
      "notfound"

  slice: (column_names, key) ->
    values = (@get(column_names, key_column) for key_column in key)
    new root.Diff.Row(values)

  equals: (other) ->
    return false unless other.values
    return false unless @values.length == other.values.length
    for i, value of @values
      return false if other.values[i] != value
    true
  isEqual: @equals

  zip: (other, func) ->
    for i, value of @values
      func(i, value, other.values[i])

  toString: ->
    result = "{root.Diff.Row values = ["
    for value in @values
      if value.toString?
        result += "#{value.toString()},"
      else
        result += "#{value},"
    result.replace(/,*$/, "]}")


class root.Diff.Index
  constructor: (key, column_names, data_set) ->
    @key = key
    @column_names = column_names
    @lookup = new Hashtable
    lkp = @lookup
    @lookup.isEqual = (other) ->
      return false unless _.isEqual(lkp.keys(), other.keys())
      for key_value in lkp.keys
        return false unless lkp.get(key_value).equals(other.get(key_value))
      true

    all_key_values = data_set.slice(column_names, key)
    for key_value in all_key_values.rows
      filtered_data_set = data_set.filter(@column_names, key, key_value)
      @lookup.put(key_value, filtered_data_set)

  key_values: ->
    new root.Diff.DataSet(@lookup.keys())

  get: (search) ->
    result = @lookup.get search
    return result if result
    new root.Diff.DataSet([])

  has_key: (search) ->
    !@get(search).is_empty()

  intersection: (other) ->
    other_keys = other.key_values()
    result = []
    for i, this_key_row of @key_values().rows
      matching_rows = other_keys.filter(@key, @key, this_key_row)
      result.push(this_key_row) unless matching_rows.is_empty()
    new root.Diff.DataSet(result)

  merge: (other) ->
    key_value = @lookup.keys()[0]
    result =
      key: @key
      values: key_value
      rows:
        lhs: @get(key_value).rows[0]
        rhs: other.get(key_value).rows[0]

  pre = (text) ->
    "<pre>#{text}</pre>"

  dump_object = (object) ->
    result = ""
    for attr, value of object
      result += "#{attr} : #{value}\n"
    result

  to_html: ->
    result = $("<div>")
    result.append(pre("Key: [#{@key}]"))
    result.append(pre("Column Names: [#{@column_names}]"))
    result.append(pre("Lookup: #{dump_object(@lookup)}"))
