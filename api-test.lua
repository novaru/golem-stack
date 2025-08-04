-- Configuration
local endpoints = {
	{ method = "GET", path = "/api/files?limit=100&offset=0", weight = 40 },
	{ method = "GET", path = "/api/files/search?q=test", weight = 25 },
	{ method = "GET", path = "/api/files/recent?limit=10", weight = 25 },
	{ method = "GET", path = "/api/files/stats", weight = 8 },
	{ method = "POST", path = "/api/files", weight = 2 },
}

-- Search queries pool
local search_queries = { "txt", "pdf", "image", "document", "test", "data", "config" }
local file_names = { "test.txt", "data.json", "image.png", "doc.pdf", "config.yml" }

-- Generate multipart form data
local function create_multipart_body(filename, content)
	local boundary = "----WebKitFormBoundary" .. math.random(100000, 999999)
	local body_parts = {}

	table.insert(body_parts, "--" .. boundary)
	table.insert(body_parts, 'Content-Disposition: form-data; name="file"; filename="' .. filename .. '"')
	table.insert(body_parts, "Content-Type: text/plain")
	table.insert(body_parts, "")
	table.insert(body_parts, content)
	table.insert(body_parts, "--" .. boundary .. "--")
	table.insert(body_parts, "")

	local body = table.concat(body_parts, "\r\n")
	local content_type = "multipart/form-data; boundary=" .. boundary

	return body, content_type
end

-- Upload test data
local upload_files = {
	{ filename = "test1.txt", content = "Hello World Test File" },
	{ filename = "data.json", content = '{"test": true, "data": "sample"}' },
	{ filename = "sample.txt", content = "Sample content for testing" },
	{ filename = "readme.md", content = "# Test File\nThis is a test file" },
}

-- Weighted random selection
local function weighted_random(items)
	local total_weight = 0
	for _, item in ipairs(items) do
		total_weight = total_weight + item.weight
	end

	local random_weight = math.random() * total_weight
	local current_weight = 0

	for _, item in ipairs(items) do
		current_weight = current_weight + item.weight
		if random_weight <= current_weight then
			return item
		end
	end

	return items[1]
end

-- Initialize
function init()
	math.randomseed(os.time())
end

-- Setup each request
function request()
	local endpoint = weighted_random(endpoints)
	local path = endpoint.path
	local method = endpoint.method
	local body = nil
	local headers = "Host: localhost:3001\r\n"

	-- Dynamic path substitution for search queries
	if string.find(path, "/search") then
		local query = search_queries[math.random(#search_queries)]
		path = "/api/files/search?q=" .. query
	end

	-- Vary list parameters
	if string.find(path, "/api/files?") and not string.find(path, "search") then
		local limit = math.random(10, 100)
		local offset = math.random(0, 50)
		path = "/api/files?limit=" .. limit .. "&offset=" .. offset
	end

	-- Vary recent parameters
	if string.find(path, "/recent") then
		local limit = math.random(5, 50)
		path = "/api/files/recent?limit=" .. limit
	end

	-- Handle POST requests with multipart/form-data
	if method == "POST" then
		local upload_file = upload_files[math.random(#upload_files)]
		local multipart_body, content_type = create_multipart_body(upload_file.filename, upload_file.content)

		body = multipart_body
		headers = headers .. "Content-Type: " .. content_type .. "\r\n"
		headers = headers .. "Content-Length: " .. string.len(body) .. "\r\n"
	end

	-- Build the complete request
	local request_line = method .. " " .. path .. " HTTP/1.1\r\n"
	local complete_request = request_line .. headers .. "\r\n"

	if body then
		complete_request = complete_request .. body
	end

	return complete_request
end

-- Response tracking
local responses = {}

function response(status, headers, body)
	responses[status] = (responses[status] or 0) + 1
end

-- Final statistics
function done(summary, latency, requests)
	print("\n" .. string.rep("=", 60))
	print("API Load Test Results")
	print(string.rep("=", 60))

	print(string.format("Requests:      %d", summary.requests))
	print(string.format("Duration:      %.2fs", summary.duration / 1000000))
	print(string.format("Req/sec:       %.2f", summary.requests / (summary.duration / 1000000)))

	-- Latency stats
	print(string.format("\nLatency:"))
	print(string.format("  Min:         %.2fms", latency.min / 1000))
	print(string.format("  Max:         %.2fms", latency.max / 1000))
	print(string.format("  Mean:        %.2fms", latency.mean / 1000))

	-- Percentiles
	print(string.format("\nPercentiles:"))
	print(string.format("  50th:        %.2fms", latency:percentile(50) / 1000))
	print(string.format("  90th:        %.2fms", latency:percentile(90) / 1000))
	print(string.format("  99th:        %.2fms", latency:percentile(99) / 1000))

	-- Status codes
	print(string.format("\nStatus Codes:"))
	for status, count in pairs(responses) do
		local percentage = (count / summary.requests) * 100
		print(string.format("  %d:          %d (%.1f%%)", status, count, percentage))
	end

	print(string.rep("=", 60))
end
