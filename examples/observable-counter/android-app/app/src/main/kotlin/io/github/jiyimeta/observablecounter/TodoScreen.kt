package io.github.jiyimeta.observablecounter

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.github.jiyimeta.observablecounter.generated.TodoListVMViewModel

@Composable
fun TodoScreen(viewModel: TodoListVMViewModel) {
    val items by viewModel.items.collectAsStateWithLifecycle()
    val totalCount by viewModel.totalCount.collectAsStateWithLifecycle()
    Surface {
        Column(modifier = Modifier.padding(16.dp).fillMaxSize()) {
            Text("total=$totalCount", modifier = Modifier.testTag("total"))
            Button(
                onClick = {
                    val next = totalCount + 1
                    viewModel.add(TodoItem(id = next, title = "task #$next", done = false))
                },
                modifier = Modifier.testTag("add"),
            ) { Text("Add") }
            Button(onClick = viewModel::clear, modifier = Modifier.testTag("clear")) {
                Text("Clear")
            }
            Spacer(Modifier.height(8.dp))
            LazyColumn(modifier = Modifier.testTag("list")) {
                items(items) { item ->
                    Row(modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                        Checkbox(checked = item.done, onCheckedChange = null)
                        Text(item.title, modifier = Modifier.padding(start = 8.dp))
                    }
                }
            }
        }
    }
}
