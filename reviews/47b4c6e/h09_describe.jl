using PDEStudio
studio_headless!(); set_save_path!(mktempdir())
launch_plotter(test_heat_2d(); style = :heatmap)
io = IOBuffer(); describe_studio(io); println(String(take!(io)))
for i in 1:4
    try
        studio_option!(:plot_style, :method_index, i)
        println("method_index = $i -> ", collect(keys(studio_state().plots[1].value_ranges)), "  status: ", studio_state().status.text)
    catch e
        println("method_index = $i -> ERR ", sprint(showerror, e))
    end
end
