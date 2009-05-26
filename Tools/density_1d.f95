!
! Calculates density of a certain element in 1D around the origin
!

program density_1d

    use libatoms_module

    implicit none
  
    integer, parameter                    :: DISTANCES_INIT = 1000000
    integer, parameter                    :: DISTANCES_INCR = 1000000
   
    type(Atoms)                           :: structure, new_structure
    type(Table)                           :: distances, atom_table
    real(dp)                              :: d
    type(Inoutput)                        :: xyzfile, datafile
    integer                               :: frame_count, frames_processed
    integer                               :: status
    integer                               :: i, j
  
    !Input
    type(Dictionary)                      :: params_in
    character(FIELD_LENGTH)               :: xyzfilename, datafilename
    real(dp)                              :: cutoff, bin_width
    character(FIELD_LENGTH)               :: mask
    integer                               :: IO_Rate
    integer                               :: decimation
    integer                               :: from, to
    logical                               :: Gaussian_smoothing
    real(dp)                              :: Gaussian_sigma
  
    !AtomMask processing
    character(30)                         :: prop_name
    logical                               :: list, prop
    integer                               :: prop_val
    integer                               :: Zb
  
    !Histogram & its integration/normalisation
    real(dp), allocatable, dimension(:,:) :: data
    real(dp), allocatable, dimension(:)   :: hist, hist_sum
    integer                               :: num_bins, num_atoms
    real(dp)                              :: hist_int
    real(dp)                              :: density, r, dV


  !Start up LOTF, suppressing messages
    call system_initialise(NORMAL)

#ifdef DEBUG
    call print('********** DEBUG BUILD **********')
    call print('')
#endif

    call initialise(params_in)
    call param_register(params_in, 'xyzfile', param_mandatory, xyzfilename)
    call param_register(params_in, 'datafile', 'data.den1', datafilename)
    call param_register(params_in, 'AtomMask', param_mandatory, mask)
    call param_register(params_in, 'Cutoff', param_mandatory, cutoff)
    call param_register(params_in, 'BinWidth', param_mandatory, bin_width)
    call param_register(params_in, 'decimation', '1', decimation)
    call param_register(params_in, 'from', '0', from)
    call param_register(params_in, 'to', '0', to)
    call param_register(params_in, 'IO_Rate', '1', IO_Rate)
    call param_register(params_in, 'Gaussian', 'F', Gaussian_smoothing)
    call param_register(params_in, 'sigma', '0.0', Gaussian_sigma)
    if (.not. param_read_args(params_in, do_check = .true.)) then
       if (EXEC_NAME == '<UNKNOWN>') then
          call print_usage
       else
          call print_usage(EXEC_NAME)
       end if
      call system_abort('could not parse argument line')
    end if
    call finalise(params_in)

    call initialise(xyzfile,xyzfilename,action=INPUT)

    call print('Run_parameters: ')
    call print('==================================')
    call print('    Input file: '//trim(xyzfilename))
    call print('   Output file: '//trim(datafilename))
    call print('      AtomMask: '//trim(mask))
    call print('        Cutoff: '//round(Cutoff,3))
    call print('      BinWidth: '//round(bin_width,3))
    call print('    decimation: '//decimation)
    call print('    from Frame: '//from)
    call print('      to Frame: '//to)
    call print('       IO_Rate: '//IO_Rate)
    call print('     Gaussians: '//Gaussian_smoothing)
    if (Gaussian_smoothing) call print('        sigma: '//round(Gaussian_sigma,3))
    call print('==================================')
    call print('')
 
    !
    ! Read the element symbol / atom mask
    !
    call print('Mask 2:')
    call print('=======')
    if (mask(1:1)=='@') then
       list = .true.
       prop = .false.
       call parse_atom_mask(mask,atom_table)
    else if (scan(mask,'=')/=0) then
       list = .true.
       prop = .true.
       call get_prop_info(mask, prop_name, prop_val)
       call print('')
       call print('Selecting all atoms that have '//trim(prop_name)//' set to '//prop_val)
       call print('')
    else
       list = .false.
       prop = .false.
       Zb = Atomic_Number(mask)
       call print('')
       write(line,'(a,i0,a)')'Selecting all '//trim(ElementName(Zb))//' atoms (Z = ',Zb,')'
       call print(line)
       call print('')
    end if
 
    if (cutoff < 0.0_dp) call system_abort('Cutoff < 0.0 Angstroms')
    if (bin_width < 0.0_dp) call system_abort('Bin width < 0.0 Angstroms')
    if (Gaussian_smoothing.and.(Gaussian_sigma.le.0._dp)) call system_abort('sigma must be > 0._dp')
 
    !Make num_bins and bin_width consistent
    num_bins = ceiling(cutoff / bin_width)
    bin_width = cutoff / real(num_bins,dp)
 
    allocate( hist(num_bins), hist_sum(num_bins), data(num_bins,3) )
 
    hist = 0.0_dp
    hist_sum = 0.0_dp
    hist_int = 0.0_dp
 
    !Set up the x coordinates of the plot
    do i = 1, num_bins
       data(i,1) = (real(i,dp) - 0.5_dp) * bin_width
    end do
 
    call print('')
    write(line,'(i0,a,f0.4,a,f0.4,a)') num_bins,' bins x ',bin_width,' Angstroms per bin = ',cutoff,' Angstroms cutoff'
    call print(line)
    call print('')
    if (decimation == 1) then
       call print('Processing every frame')
    else
       write(line,'(a,i0,a,a)')'Processing every ',decimation,th(decimation),' frame'
       call print(line)
    end if
    call print('')
 
    call print('Reading data...')
 
    !Set up cells
!    call read_xyz(new_structure, xyzfile, status=status)
    call read_xyz(structure, xyzfile, status=status)
 
!    structure = new_structure
    call atoms_set_cutoff(structure,cutoff)
 
    call allocate(distances,0,1,0,0,DISTANCES_INIT)
    call set_increment(distances,DISTANCES_INCR)
 
    frame_count = 0
    frames_processed = 0
 
    do
     
       if (status/=0) exit
  
       !Skip ahead (decimation-1) frames in the xyz file
       frame_count = frame_count + 1
       do i = 1, (decimation-1)
          call read_xyz(xyzfile,status)
          if (status/=0) exit
          frame_count = frame_count + 1
       end do
  
       if (status.ne.0) then
          call print('double exit')
          exit
       endif
  
       write(mainlog%unit,'(a,a,i0,$)') achar(13),'Frame ',frame_count
  
       if (frame_count.ge.from) then
          if ((frame_count.gt.to) .and.(to.gt.0)) exit
  
          !Copy the read data into the working atoms object
!          if (structure%N == new_structure%N) then
!             structure = new_structure
!          else
!             structure = new_structure
             call atoms_set_cutoff(structure,cutoff)
!          end if
  
          if (prop) call update_list(structure,atom_table,trim(prop_name),prop_val)
       
          call wipe(distances)
       
          num_atoms = 0
     
          do j = 1, structure%N
          
             !Count the atoms
             if (list) then
                if (find(atom_table,j)/=0) num_atoms = num_atoms + 1
             else
                if (structure%Z(j) == Zb) num_atoms = num_atoms + 1
             end if
          
             !Do we have a "Mask" atom? Cycle if not
             if (list) then
                if (find(atom_table,j)==0) cycle
             else
                if (structure%Z(j) /= Zb) cycle
             end if

             d = distance_min_image(structure,j,(/0._dp,0._dp,0._dp/))
             if (d < cutoff) then
#ifdef DEBUG
                call print('Storing distance (/0,0,0/)--'//j//' = '//round(d,5)//'A')
#endif
                !Add this distance to the list
                call append(distances, d)
             end if
             
          end do
           
          frames_processed = frames_processed + 1
     
#ifdef DEBUG
          call print('Number of atoms = '//num_atoms)
#endif
     
          !Calculate histogram
          if (.not.Gaussian_smoothing) then
             hist = histogram(distances%real(1,1:distances%N), 0.0_dp, cutoff, num_bins)
          else
             hist = Gaussian_histogram(distances%real(1,1:distances%N), 0.0_dp, cutoff, num_bins,Gaussian=Gaussian_smoothing,sigma=Gaussian_sigma)
          endif
     
          !Calculate B atom density
          density = real(num_atoms,dp) / cell_volume(structure)
     
          !Normalise histogram
          do i = 1, num_bins
             r = (real(i,dp) - 1._dp) * bin_width
             dV = 4.0_dp * PI * (r*r + r*bin_width + bin_width*bin_width/3.0_dp ) * bin_width
             hist(i) = hist(i) / (dV * density * 1._dp)
          end do
        
          !Accumulate the data
          hist_sum = hist_sum + hist
          
          !copy the current averages into the y coordinates of the plot
          data(:,2) = hist_sum / real(frames_processed,dp)
      
          !integrate the average data
          hist_int = 0.0_dp
          do i = 1, num_bins
             r = data(i,1)
             dV = PI * (4.0_dp * r*r + bin_width*bin_width/3.0_dp) * bin_width
             hist_int = hist_int + data(i,2)*dV*density
             data(i,3) = hist_int
          end do
           
          !Write the current data. This allows the user to Ctrl-C after a certain number
          !of frames if things are going slowly
          if (mod(frames_processed,IO_Rate)==0) then
             call initialise(datafile,datafilename,action=OUTPUT)
             call print('# Density 1D',file=datafile)
             call print('# Input file: '//trim(xyzfilename),file=datafile)
             call print('#      Frames read = '//frame_count,file=datafile)
             call print('# Frames processed = '//frames_processed,file=datafile)
             call print(data,file=datafile)
             call finalise(datafile)
          endif
       endif     
     
       !Try to read another frame
!       call read_xyz(new_structure,xyzfile,status=status)
       call read_xyz(structure,xyzfile,status=status)
        
    end do
  
    call print('')
    call print('Read '//frame_count//' frames, processed '//frames_processed//' frames.')
  
    !Free up memory
    call finalise(distances)
    call finalise(structure)
    call finalise(xyzfile)
  
    deallocate(hist, hist_sum, data)
  
    call print('Finished.')
  
    !call verbosity_pop
    call system_finalise

contains

  subroutine print_usage(name)

    character(*), optional, intent(in) :: name

    if (present(name)) then
       write(line,'(3a)')'Usage: ',trim(name),' xyzfile datafile AtomMask Cutoff BinWidth [decimation] [from] [to] [IO_Rate] [Gaussian] [sigma]'
    else
       write(line,'(a)')'Usage: density_1d xyzfile datafile AtomMask Cutoff BinWidth [decimation] [from] [to] [IO_Rate] [Gaussian] [sigma]'
    end if
    call print(line)
    call print(' <xyzfile>       The input xyz file.')
    call print(' <AtomMask>      An element symbol, e.g. H or Ca, or @ followed by a list of indices/ranges, e.g. @1-35,45,47,50-99 or property=value')
    call print(' <Cutoff>        The cutoff radius in Angstroms.')
    call print(' <BinWidth>      The width of each bin in Angstroms.')
    call print(' <datafile>      The output data file.')
    call print(' <decimation>    Optional. Only process 1 out of every n frames.')
    call print(' <from>          Optional. Only process frames from this frame.')
    call print(' <to>            Optional. Only process frames until this frame.')
    call print(' <IO_Rate>       Optional. Write data after every n processed frames.')
    call print(' <Gaussian>      Optional. Use Gaussians instead of delta functions.')
    call print(' <sigma>         Optional. The sigma is the sqrt(variance) of the Gaussian function.')
    call print('')
    call print('Pressing Ctrl-C during execution will leave the output file with the rdf averaged over the frames read so far')
    call print('')

    !call verbosity_pop
    call system_finalise
    stop
        
  end subroutine print_usage

  subroutine get_prop_info(mask,name,value)

    character(*), intent(in)  :: mask
    character(*), intent(out) :: name
    integer,      intent(out) :: value
    integer                   :: delimiter

    delimiter = scan(mask,'=')
    if (delimiter > 1) then
       name = adjustl(mask(1:delimiter-1))
       value = string_to_int(mask(delimiter+1:len_trim(mask)))
    else
       call system_abort('Zero length property name in mask: "'//trim(mask)//'"')
    end if

  end subroutine get_prop_info

  subroutine update_list(at,list,name,value)

    type(atoms), intent(in)    :: at
    type(table), intent(inout) :: list
    character(*), intent(in)   :: name
    integer,     intent(in)    :: value

    integer                    :: i, pos_indices(3), index

    !find property
    if (get_value(at%properties,name,pos_indices)) then
       index = pos_indices(2)
    else
       call system_abort('Property "'//name//'" not found')
    end if

    call wipe(list)
    
    do i = 1, at%N

       if (at%data%int(index,i)==value) call append(list,(/i/))

    end do

  end subroutine update_list

  function Gaussian_histogram(vector,min_x,max_x,Nbin,Gaussian,sigma)

    real(dp), dimension(:), intent(in) :: vector
    real(dp),               intent(in) :: min_x, max_x
    integer,                intent(in) :: Nbin
    logical,       intent(in) :: Gaussian
    real(dp),      intent(in) :: sigma
    real(dp), dimension(Nbin)          :: Gaussian_histogram
    !local variables
    real(dp)                           :: binsize,min_bin,max_bin
    integer                            :: i, bin, j
  
    if(max_x <= min_x) then
       call system_abort('Vector_Histogram: max_x < min_x')
    end if

    binsize=(max_x-min_x)/(real(Nbin,dp))
    Gaussian_histogram = 0.0_dp

    do i=1,size(vector)
       call print('')
       call print('Distribution of vector '//i//' over the whole histogram:')

       if (Gaussian) then
!          if(.not.present(sigma)) call system_abort('Gaussian_histogram: Missing Gaussian sigma parameter.')
          do j=1,Nbin
             min_bin = min_x + real(j-1,dp) * binsize
             max_bin = min_bin + binsize
             call print('min_bin: '//min_bin//', max_bin: '//max_bin)
             call print('ERF(min_bin) = '//erf((vector(i)-min_bin)/(sigma*sqrt(2._dp))))
             call print('ERF(max_bin) = '//erf((max_bin-vector(i))/(sigma*sqrt(2.0_dp))))
             call print('Adding to bin '//j//' '//erf((vector(i)-min_bin)/(sigma*sqrt(2._dp))) + erf((max_bin-vector(i))/(sigma*sqrt(2.0_dp))))
             Gaussian_histogram(j) = Gaussian_histogram(j) - 0.5_dp*erf((min_bin-vector(i))/(sigma*sqrt(2._dp))) + 0.5_dp*erf((max_bin-vector(i))/(sigma*sqrt(2.0_dp)))
          enddo
       else
          bin = ceiling((vector(i)-min_x)/binsize)
          if (bin < 1) bin = 1
          if (bin > Nbin) bin = Nbin
          Gaussian_histogram(bin) = Gaussian_histogram(bin) + 1.0_dp
       endif
    end do

  end function Gaussian_histogram

end program density_1d
