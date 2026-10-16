import win.browser
import lib.assert

int main():
	win_browser* browser = new win_browser()
	win_interactive_worker* worker = new win_interactive_worker()
	browser.interactive = worker
	worker.child = new process()
	worker.generation = 9
	worker.document_generation = 3
	worker.viewport_width = 800
	worker.viewport_height = 600
	worker.input_present = 1
	worker.input_queue = new list[win_interactive_input*]
	for i in range(3):
		win_interactive_input* batch = new win_interactive_input()
		batch.generation = 9
		batch.document = 3
		batch.width = 800
		batch.height = 600
		if (i == 0): batch.history_delta = -1
		if (i == 2): batch.history_delta = 1
		worker.input_queue.push(batch)
	win_browser_interactive_cancel(browser)
	assert_equal(3, worker.input_queue.length)
	assert_equal(-1, worker.input_queue[0].history_delta)
	assert_equal(1, worker.input_queue[1].history_delta)
	assert_equal(GFX_EVENT_POINTER_CANCEL, worker.input_queue[2].native.events[0].kind)
	assert_equal(0, worker.input_present)
	win_browser_interactive_cancel(browser)
	assert_equal(3, worker.input_queue.length)
	assert_equal(-1, worker.input_queue[0].history_delta)
	assert_equal(1, worker.input_queue[1].history_delta)
	assert_equal(GFX_EVENT_POINTER_CANCEL, worker.input_queue[2].native.events[0].kind)
	for win_interactive_input* batch in worker.input_queue: free(batch)
	__w_list_free(cast(__w_list*,worker.input_queue))
	free(worker.child)
	free(worker)
	free(browser)
	assert_equal(0, debug_alloc_report_leaks())
	println(c"Cancellation preserves ordered history, drops unsent input, and does not accumulate cancel packets: OK")
	return 0
