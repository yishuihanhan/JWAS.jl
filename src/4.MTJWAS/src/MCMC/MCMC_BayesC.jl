function MCMC_BayesC(nIter,mme,df,Pi;
                      sol=false,outFreq=0,
                      missing_phenotypes=false,
                      constraint=false,
                      estimatePi=false,
                      methods="BayesC0",
                      output_samples_frequency=0)

    if size(mme.mmeRhs)==()
       getMME(mme,df)
    end

    if sol == false
       sol=zeros(size(mme.mmeLhs,1))
    end #starting value for sol can be provided

    p = size(mme.mmeLhs,1)
    solMean = fill(0.0,p)

    #priors for residual covariance matrix
    ν       = 4
    nObs    = size(df,1)
    nTraits = size(mme.lhsVec,1)
    νR0     = ν + nTraits
    R0      = mme.R
    PRes    = R0*(νR0 - nTraits - 1)
    SRes    = zeros(Float64,nTraits,nTraits)
    R0Mean  = zeros(Float64,nTraits,nTraits)
    scaleRes= diag(mme.R)*(ν-2)/ν #for chisq for constrant diagonal R

    #priors for polygenic effect variance matrix
    if mme.ped != 0
        ν         = 4
        pedTrmVec = mme.pedTrmVec
        k         = size(pedTrmVec,1)
        νG0       = ν + k
        G0        = inv(mme.Gi)
        P         = G0*(νG0 - k - 1)
        S         = zeros(Float64,k,k)
        G0Mean    = zeros(Float64,k,k)
    end

    #priors for marker covaraince matrix
    nObs,nMarkers  = size(mme.M.genotypes)
    dfEffectVar    = 4.0
    mGibbs         = GibbsMats(mme.M.genotypes)
    nObs           = mGibbs.nrows
    nMarkers       = mGibbs.ncols
    mArray         = mGibbs.xArray
    mpm            = mGibbs.xpx
    M              = mGibbs.X
    vEff           = mme.M.G
    νGM            = dfEffectVar + nTraits
    PM             = vEff*(νGM - nTraits - 1)
    SM             = zeros(Float64,nTraits,nTraits)
    GMMean         = zeros(Float64,nTraits,nTraits)

    #priors for π
    if methods == "BayesC"
      if Pi == 0.0
        error("Pi is not provided!!")
      end
      BigPi = copy(Pi)
      BigPiMean = copy(Pi)
      for key in keys(BigPiMean)
        BigPiMean[key]=0.0
      end

    elseif methods == "BayesCC"
      if Pi == 0.0
        error("Pi is not provided!!")
      end
      #label with the index of Array
      #labels[1]=[0.0,0.0],labels[2]=[1.0,1.0]
      #BigPi[1]=0.3,BigPi[2]=0.7
      nlabels= length(Pi)
      labels = Array(Array{Float64,1},nlabels)
      BigPi  = Array(Float64,nlabels)
      whichlabel=1
      for pair in sort(collect(Pi), by=x->x[2],rev=true)
        key=pair[1]
        labels[whichlabel]=copy(key)
        BigPi[whichlabel]=copy(pair[2])
        whichlabel = whichlabel+1
      end
      BigPiMean = zeros(BigPi)

    elseif methods == "BayesC0"
      if estimatePi==true
        error("Estimating π is not allowed in BayesC0")
      end
    end


    #starting values for marker effects are all zeros
    #starting values for other location parameters are sol
    ycorr          = vec(full(mme.ySparse))
    wArray         = Array(Array{Float64,1},nTraits)
    alphaArray     = Array(Array{Float64,1},nTraits)
    meanAlphaArray = Array(Array{Float64,1},nTraits)
    deltaArray     = Array(Array{Float64,1},nTraits) #BayesC
    meanDeltaArray = Array(Array{Float64,1},nTraits) #BayesC
    uArray         = Array(Array{Float64,1},nTraits) #BayesC
    meanuArray     = Array(Array{Float64,1},nTraits) #BayesC

    for traiti = 1:nTraits
        startPosi              = (traiti-1)*nObs  + 1
        ptr                    = pointer(ycorr,startPosi)
        wArray[traiti]         = pointer_to_array(ptr,nObs) #ycorr for different traits
                                                            #wArray is list version reference of ycor
        alphaArray[traiti]     = zeros(nMarkers)
        meanAlphaArray[traiti] = zeros(nMarkers)
        deltaArray[traiti]     = zeros(nMarkers)
        meanDeltaArray[traiti] = zeros(nMarkers)
        uArray[traiti]         = zeros(nMarkers)
        meanuArray[traiti]     = zeros(nMarkers)
    end


    if output_samples_frequency != 0
      #initialize arrays to save MCMC samples
      array4samples = init_sample_arrays(mme,Int(floor(nIter/output_samples_frequency)))
      out_i = 1
      #write samples for marker effects to a txt file
      outfile = Array{IOStream}(nTraits)
      for traiti in 1:nTraits
        outfile[traiti]=open("marker_effects"*"_"*string(mme.lhsVec[traiti])*"_$(now()).txt","w")
      end

      if mme.M.markerID[1]!="NA"
        for traiti in 1:nTraits
            writedlm(outfile[traiti],mme.M.markerID')
        end
      end
    end

    #MCMC
    @showprogress "running MCMC for "*methods*"..." for iter=1:nIter
        #####################################
        #sample non-marker location parameter
        #####################################
        Gibbs(mme.mmeLhs,sol,mme.mmeRhs)
        ycorr[:] = ycorr[:] - mme.X*sol

        #####################################
        #sample marker effects
        #####################################
        iR0,iGM = inv(mme.R),inv(mme.M.G)
        if methods == "BayesC"
          sampleMarkerEffectsBayesC!(mArray,mpm,wArray,
                                    alphaArray,meanAlphaArray,
                                    deltaArray,meanDeltaArray,
                                    uArray,meanuArray,
                                    iR0,iGM,iter,BigPi)
        elseif methods == "BayesC0"
          sampleMarkerEffects!(mArray,mpm,wArray,alphaArray,
                               meanAlphaArray,iR0,iGM,iter)
        elseif methods == "BayesCC"
          sampleMarkerEffectsBayesCC!(mArray,mpm,wArray,
                                     alphaArray,meanAlphaArray,
                                     deltaArray,meanDeltaArray,
                                     uArray,meanuArray,
                                     iR0,iGM,iter,BigPi,labels)
        end

        if estimatePi == true
          if methods == "BayesC"
            samplePi(deltaArray,BigPi,BigPiMean,iter)
          elseif methods == "BayesCC"
            samplePi(deltaArray,BigPi,BigPiMean,iter,labels)
          end
        end

        #####################################
        #sample residual covariance matrix
        #AND marker covariance matrix
        #####################################
        resVec = ycorr
        if missing_phenotypes==true
          sampleMissingResiduals(mme,resVec)
        end

        for traiti = 1:nTraits
            startPosi = (traiti-1)*nObs + 1
            endPosi   = startPosi + nObs - 1
            for traitj = traiti:nTraits
                startPosj = (traitj-1)*nObs + 1
                endPosj   = startPosj + nObs - 1
                SRes[traiti,traitj] = (resVec[startPosi:endPosi]'resVec[startPosj:endPosj])[1,1]
                SRes[traitj,traiti] = SRes[traiti,traitj]
                SM[traiti,traitj]   = (alphaArray[traiti]'alphaArray[traitj])[1]
                SM[traitj,traiti]   = SM[traiti,traitj]
            end
        end

        mme.M.G = rand(InverseWishart(νGM + nMarkers, PM + SM))
        R0      = rand(InverseWishart(νR0 + nObs, PRes + SRes))

        #for constraint R, chisq
        if constraint == true
          R0 = zeros(nTraits,nTraits)
          for traiti = 1:nTraits
            R0[traiti,traiti]= (SRes[traiti,traiti]+ν*scaleRes[traiti])/rand(Chisq(nObs+ν))
          end
        end

        mme.R = R0
        if missing_phenotypes==true
          RiNotUsing   = mkRi(mme,df) #for missing value;updata mme.ResVar
        end
        R0    = mme.R
        Ri    = kron(inv(R0),speye(nObs))

        X          = mme.X
        mme.mmeLhs = X'Ri*X
        ycorr[:]   = ycorr[:] + mme.X*sol
        mme.mmeRhs = mme.X'Ri*ycorr

        #####################################
        #sample genetic variance matrix (polygenic effects)
        #can make this more efficient by taking advantage of symmetry
        #####################################
        if mme.ped != 0
            for (i,trmi) = enumerate(pedTrmVec)
                pedTrmi  = mme.modelTermDict[trmi]
                startPosi  = pedTrmi.startPos
                endPosi    = startPosi + pedTrmi.nLevels - 1
                for (j,trmj) = enumerate(pedTrmVec)
                    pedTrmj  = mme.modelTermDict[trmj]
                    startPosj  = pedTrmj.startPos
                    endPosj    = startPosj + pedTrmj.nLevels - 1
                    S[i,j] = (sol[startPosi:endPosi]'*mme.Ai*sol[startPosj:endPosj])[1,1]
                end
            end
            pedTrm1 = mme.modelTermDict[pedTrmVec[1]]
            q = pedTrm1.nLevels
            G0 = rand(InverseWishart(νG0 + q, P + S))
            mme.Gi = inv(G0)
            addA(mme)

            G0Mean  += (G0  - G0Mean )/iter
        end

        solMean += (sol - solMean)/iter
        R0Mean  += (R0  - R0Mean )/iter
        GMMean  += (mme.M.G  - GMMean)/iter

        if iter%outFreq==0
            println("\nPosterior means at iteration: ",iter)
            println("Residual covariance matrix: \n",round(R0Mean,3))
            println("Marker effects covariance matrix: \n",round(GMMean,3))
            if methods=="BayesC" && estimatePi == true
              println("π: \n",BigPiMean)
            elseif methods=="BayesCC" && estimatePi == true
              println("π for ", labels)
              println(round(BigPiMean,3))
            end
            println()
        end

        if output_samples_frequency != 0  #write samples for marker effects to a txt file
          if iter%output_samples_frequency==0
            array4samples.samples4R[out_i]=R0
            if mme.ped != 0
              array4samples.samples4G[out_i]=G0
            end
            out_i +=1
            for traiti in 1:nTraits
              if methods == "BayesC" || methods=="BayesCC"
                writedlm(outfile[traiti],uArray[traiti]')
              elseif methods == "BayesC0"
                writedlm(outfile[traiti],alphaArray[traiti]')
              end
            end
          end
        end
    end


    output = Dict()

    if output_samples_frequency != 0  #write samples for marker effects to a txt file
        for traiti in 1:nTraits
           close(outfile[traiti])
        end
          output["MCMC samples for residual covariance matrix"]= array4samples.samples4R
        if mme.ped != 0
          output["MCMC samples for polygenic effects covariance matrix"]  = array4samples.samples4G
        end
    end

    output["Posterior mean of location parameters"]    = [getNames(mme) solMean]
    output["Posterior mean of marker effects covariance matrix"] = GMMean
    output["Posterior mean of residual covariance matrix"]       = R0Mean

    if mme.ped != 0
      output["Posterior mean of polygenic effects covariance matrix"] = G0Mean
      if output_samples_frequency != 0
        output["MCMC samples for polygenic effects covariance matrix"]  = array4samples.samples4G
      end
    end

    if mme.M.markerID[1]!="NA"
      markerout        = []
      if methods == "BayesC"||methods=="BayesCC"
        for markerArray in meanuArray
          push!(markerout,[mme.M.markerID markerArray])
        end
      elseif methods == "BayesC0"
        for markerArray in meanAlphaArray
          push!(markerout,[mme.M.markerID markerArray])
        end
      end
    else
      if methods == "BayesC"||methods=="BayesCC"
        markerout        = meanuArray
      elseif methods == "BayesC0"
        markerout        = meanAlphaArray
      end

    end

    output["Posterior mean of marker effects"] = markerout
    if estimatePi == true
      output["Posterior mean of Pi"] = BigPiMean
    end

    return output
end
