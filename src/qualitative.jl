# Run some qualitative analysis
using Dates
using DataFrames
# using CSV
using Statistics
using LinearAlgebra
using BenchmarkTools

using Plots
pyplot()

# import PyPlot; const plt = PyPlot.plt

include("utils.jl")
include("Corpora.jl")

include("GloVe.jl")
include("Bias.jl")


# Combine diff_bias files
function load_df(target, bias_col=:ΔBIF_1; diff_bias_dir="results/diff_bias")
    df = DataFrame()
    i = 0
    cols = []
    for f in readdir(diff_bias_dir)
        if occursin(Regex(target), f)
            i += 1
            tmp = sort(readtable(joinpath(diff_bias_dir, f)), :doc_num)
            if (i == 1)
                df[:doc_num] = tmp[:doc_num]
            end
            col = Symbol("ΔBIF_$(i)")
            df[col] = tmp[bias_col]
            push!(cols, col)
        end
    end
    println("Loaded $i differential bias results")
    df[:ΔBIF_μ] = [mean([row[col] for col in cols]) for row in eachrow(df)]
    df[:ΔBIF_σ] = [std([row[col] for col in cols]) for row in eachrow(df)]
    return df
end


# Format metadata for a DataFrame
function meta2dict(corpus)
    meta_dict = Dict("doc_num"=>[])
    for field in corpus.fields
        meta_dict[field] =[]
    end

    for (idx, article_meta) in enumerate(corpus.index)
        push!(meta_dict["doc_num"], idx)
        for field in corpus.fields
            push!(meta_dict[field], get(article_meta, field, missing))
        end
    end
    return meta_dict
end


# List most biased articles
function list_most_biased(df, corpus, T=1000; outdir="results", name="")
    docs = sort(df, :ΔBIF_μ)[[:doc_num, :ΔBIF_μ]]
    N = size(docs, 1)

    open(joinpath(outdir, "$name-correctors.csv"), "w") do f
        for i in 1:T
            doc_num = Int(docs[i, 1])
            ΔBIF_μ = docs[i, 2]
            meta = corpus.index[doc_num]
            headline = meta["headline"]
            if headline == nothing
                headline = missing
            end
            println(f, "$doc_num ($(round(ΔBIF_μ, digits=2))): $headline")
        end
    end

    open(joinpath(outdir, "$name-aggravators.csv"), "w") do f
        for i in T:-1:1
            doc_num = Int(docs[N - T + i, 1])
            ΔBIF_μ = docs[N - T + i , 2]
            meta = corpus.index[doc_num]
            headline = meta["headline"]
            if headline == nothing
                headline = missing
            end
            println(f, "$doc_num ($(round(ΔBIF_μ, digits=2))): $headline")
        end
    end
end


# Interactive Helpers
# Get count of weat words in text
function weat_word_counts(text, weat_word_set)
    word_array = split(text)
    weat_words =[word for set in weat_word_set for word in set]
    weat_counts = Dict([(w, count(x->x==w, word_array)) for w in weat_words])
    return weat_counts
end


# Print document
function print_doc(doc_num, corpus; weat_word_set=nothing)
    meta = corpus.index[doc_num]
    text = Corpora.get_text(corpus, doc_num)
    open("results/doc.txt", "w") do f
        for (key, val) in pairs(meta)
            println(f, "$key: $(repr(val))")
        end
        println(f)
        if weat_word_set != nothing
            for (word, counts) in weat_word_counts(text, weat_word_set)
                if counts > 0
                    println(f, "$word: $counts")
                end
            end
            println(f)
        end
        println(f, text)
    end
end


# Visualization Helpers
function cossim_matrix(S::AbstractArray, T::AbstractArray, A::AbstractArray,
                       B::AbstractArray)
    Ŝ = Bias.normalize_rows(S)
    T̂ = Bias.normalize_rows(T)
    Â = Bias.normalize_rows(A)
    B̂ = Bias.normalize_rows(B)
    return [(Ŝ * Â') (Ŝ * B̂');  (T̂ * Â') (T̂ * B̂')]
end


function plot_weat(vec_set, weat_word_set)
    cos_mat = cossim_matrix(vec_set...)
    ylab = [weat_word_set.S ...; weat_word_set.T ...]
    xlab = [weat_word_set.A ...; weat_word_set.B ...]
    es = Bias.effect_size(vec_set...)
    print("WEAT - effect_size: $(round(es, digits=4))")
    heatmap(xlab, ylab, cos_mat, aspect_ratio=1, ticks=:all)
    xaxis!(xrotation=90)
    title!("WEAT - Cossim Matrix")
end

# Sanity Check
# test_vec_set = (S = rand(8, 20), T = ones(8, 20), A = ones(8,20), B = rand(8,20))
# plot_weat(test_vec_set, Bias.WEAT_WORD_SETS[1])


function plot_delta_weat(og_vec_set, new_vec_set, weat_word_set)
    og_cos_mat = cossim_matrix(og_vec_set...)
    new_cos_mat = cossim_matrix(new_vec_set...)
    ylab = [weat_word_set.S ...; weat_word_set.T ...]
    xlab = [weat_word_set.A ...; weat_word_set.B ...]
    diff_bias = Bias.effect_size(og_vec_set...) - Bias.effect_size(new_vec_set...)
    print("WEAT - diff bias: $(round(diff_bias, digits=4))")
    heatmap(xlab, ylab, og_cos_mat-new_cos_mat, aspect_ratio=1, ticks=:all)
    xaxis!(xrotation=90)
    title!("Delta Cossim Matrix")
end


# REPL Main
corpus = Corpora.Corpus("corpora/nytselect.txt")
target="C1-V15-W8-D200-R0.05-E150"
fileinfo(target)
meta_df = DataFrame(meta2dict(corpus))

# Original Diff Bias
bias_df = load_df(target, :ΔBIF_1)
df = join(bias_df[[:doc_num, :ΔBIF_μ]], meta_df, on=:doc_num)
list_most_biased(df, corpus; outdir="results/diff_bias/", name="NYT-B1")

# Weighted Diff Bias
w_bias_df = load_df(target, :ΔBIF_1, diff_bias_dir="results/weighted_diff_bias")
w_df = join(w_bias_df[[:doc_num, :ΔBIF_μ]], meta_df, on=:doc_num)
list_most_biased(w_df, corpus; outdir="results/weighted_diff_bias/", name="W-NYT-B1")

# Visualize
text = Corpora.get_text(corpus, 1117880)
M = GloVe.load_model("embeddings/vectors-C1-V15-W8-D200-R0.05-E150-S1.bin")
X_weat = GloVe.load_cooc("embeddings/cooc-C1-V15-W8.weat.bin", M.V)
weat_idx_sets = [Bias.get_weat_idx_set(set, M.vocab)
                 for set in Bias.WEAT_WORD_SETS]
all_weat_indices = unique([i for set in weat_idx_sets
                           for inds in set for i in inds])

# Play around in REPL
function p(doc_num)
    print_doc(doc_num, corpus, weat_word_set=Bias.WEAT_WORD_SETS[1])
    text = Corpora.get_text(corpus, doc_num)
    deltas = GloVe.compute_IF_deltas(text, M, X_weat, all_weat_indices)
    og_weat_vecs = Bias.make_weat_vec_set(M.W, weat_idx_sets[1])
    new_weat_vecs = Bias.make_weat_vec_set(M.W, weat_idx_sets[1], deltas=deltas)
    plot_delta_weat(og_weat_vecs, new_weat_vecs, Bias.WEAT_WORD_SETS[1])
end

p(942302)
