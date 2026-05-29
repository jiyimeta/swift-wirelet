package io.github.jiyimeta.observablecounter

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import io.github.jiyimeta.observablecounter.generated.TodoListVMViewModel

class MainActivity : ComponentActivity() {
    private val viewModel: TodoListVMViewModel by viewModels { ViewModelFactory }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { TodoScreen(viewModel) }
    }
}

private object ViewModelFactory : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass.isAssignableFrom(TodoListVMViewModel::class.java)) {
            return TodoListVMViewModel.create() as T
        }
        throw IllegalArgumentException("Unknown ViewModel class: $modelClass")
    }
}
