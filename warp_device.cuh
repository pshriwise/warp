inline __device__ float get_rand(unsigned* in)
{
/*
increments the random number with LCRNG 
adapated from OpenMC again
values from http://www.ams.org/journals/mcom/1999-68-225/S0025-5718-99-00996-5/S0025-5718-99-00996-5.pdf
since 32-bit math is being used, 30 bits are used here
*/
	const unsigned a   		= 116646453;		 		// multiplier
	const unsigned c   		= 7;						// constant add, must be odd
	const unsigned mask   	= 1073741823; 				// 2^30-1
	const float norm   		= 9.31322574615478515625E-10;	// 2^-30
	unsigned nextint = (a * in[0] +  c) & mask; 			// mod by truncation
	float randout = nextint*norm;
	if(randout>=1.0){
		randout=0.9999999;
		//printf("RN=1.0  %u %u %10.8E\n",in[0],nextint,randout);
	}
	in[0]=nextint;
	return randout;   						// return normalized float
}

inline __device__ float interpolate_linear_energy(float this_E, float e0, float e1, float var0, float var1){
/*
linearly interpolates between energy points
*/

	float	f	=	(this_E - e0) / (e1 - e0);
	return  var0 + f*(var1 - var0);

}


inline __device__ float interpolate_continuous_tablular_histogram( float rn , float var , float cdf , float pdf ){
/*
histogram interpolation for angular data
*/

	return var + (rn - cdf)/pdf;

}

inline __device__ float interpolate_continuous_tablular_linlin( float rn , float var0 , float var1 , float cdf0 , float cdf1 , float pdf0 , float pdf1 ){
/*
linear-linear interpolation for angular data
*/
	// check
	float m = (pdf1-pdf0)/(var1-var0);
	if (m!=0.0){
		return var0  +  (sqrtf( pdf0*pdf0 - 2.0*m*(rn-cdf0) ) - pdf0  ) / m;
	}
	else{
		// limit at m=0 is histogram interpolation
		return interpolate_continuous_tablular_histogram( rn, var0, cdf0, pdf0 );
	}

}


inline __device__ float sum_cross_section( unsigned length , float energy0, float energy1, float this_E, float* multiplier, float* array0, float* array1){
/*
Calculates the sum of a cross section range.  This routine has a multiplier array and two arrays  / two energy_ins for inside the data.  Returns sum.
*/
	float macro_t_total = 0.0;

	for( int k=0; k<length; k++ ){
		// interpolate and accumulate
		macro_t_total += ( (array1[k]-array0[k])/(energy1-energy0)*(this_E-energy0) + array0[k] ) * multiplier[k];
	}

	return macro_t_total;

}

inline __device__ float sum_cross_section( unsigned length , float energy0, float this_E, float* multiplier, float* array0){
/*
Calculates the sum of a cross section range.  This routine has a multiplier array and one array / one energy_in for outside the data.  Returns sum.
*/
	float macro_t_total = 0.0;

	// multiply and accumuate at the end
	for( int k=0; k<length; k++ ){
		macro_t_total += array0[k] * multiplier[k];
	}

	// if below, scale as 1/v
	if (this_E < energy0){
		return macro_t_total * sqrtf(energy0/this_E);
	}
	else{
		return macro_t_total;
	}

}

inline __device__ float sum_cross_section( unsigned length , float energy0, float energy1, float this_E, float* array0, float* array1){
/*
Calculates the sum of a cross section range.  This routine has no multiplier array, and two arrays / two energy_ins for inside the data.  Returns sum.
*/
	float macro_t_total = 0.0;

	for( int k=0; k<length; k++ ){
		//linearly interpolate and accumulate
		macro_t_total += ( (array1[k]-array0[k])/(energy1-energy0)*(this_E-energy0) + array0[k] );
	}

	return macro_t_total;

}

inline __device__ float sum_cross_section( unsigned length , float energy0, float this_E, float* array0){
/*
Calculates the sum of a cross section range.  This routine has no multiplier array and one array / one energy_in for outside the data.  Returns sum.
*/
	float macro_t_total = 0.0;

	// multiply and accumuate at the end
	for( int k=0; k<length; k++ ){
		macro_t_total += array0[k];
	}

	// if below, scale as 1/v
	if (this_E < energy0){
		return macro_t_total * sqrtf(energy0/this_E);
	}
	else{
		return macro_t_total;
	}

}

inline __device__ unsigned sample_cross_section( unsigned length , float normalize, float rn, float energy0, float energy1, float this_E, float* multiplier, float* array0, float* array1){
/*
Samples the isotope/reaction once a normalization factor is known (material/isotope total macroscopic cross section).  This routine HAS a multiplier array.  Returns array index.
*/
	unsigned	index				= 0;
	float		cumulative_value	= 0.0;

	for( index=0; index<length; index++ ){
		//linearly interpolate and accumulate
		cumulative_value += ( (array1[index]-array0[index])/(energy1-energy0)*(this_E-energy0) + array0[index] ) * multiplier[index] / normalize;
		if ( rn <= cumulative_value ){
			break;
		}
	}

	if( index == length ){
		index--;
		printf("SAMPLED GAP IN sample_cross_section: E %6.4E rn %12.10E normalize %10.12E\n",this_E,rn,normalize);
	}

	return index;

}

inline __device__ unsigned sample_cross_section( unsigned length , float normalize, float rn, float energy0, float this_E, float* multiplier, float* array0){
/*
Samples the isotope/reaction once a normalization factor is known (material/isotope total macroscopic cross section).  This routine HAS a multiplier array and one energy_in / array for ouside of data.  Returns array index.
*/
	unsigned	index				= 0;
	float		cumulative_value	= 0.0;

	// if below, apply 1/v scaling uniformly instead of multiplying a much of times
	if (this_E < energy0){
		normalize = normalize / sqrtf(energy0/this_E);
	}

	// sample
	for( index=0; index<length; index++ ){
		//linearly interpolate and accumulate
		cumulative_value +=  array0[index] * multiplier[index] / normalize;
		if ( rn <= cumulative_value ){
			break;
		}
	}

	if( index == length ){
		index--;
		printf("SAMPLED GAP IN sample_cross_section: E %6.4E rn %12.10E normalize %10.12E\n",this_E,rn,normalize);
	}

	return index;

}



inline __device__ unsigned sample_cross_section( unsigned length , float normalize, float rn, float energy0, float energy1, float this_E, float* array0, float* array1){
/*
Samples the isotope/reaction once a normalization factor is known (material/isotope total macroscopic cross section).  Returns array index.
*/
	unsigned	index				= 0;
	float		cumulative_value	= 0.0;

	for( index=0; index<length; index++ ){
		//linearly interpolate and accumulate
		cumulative_value += ( (array1[index]-array0[index])/(energy1-energy0)*(this_E-energy0) + array0[index] ) / normalize;
		if ( rn <= cumulative_value ){
			break;
		}
	}

	if( index == length ){
		index--;
		printf("SAMPLED GAP IN sample_cross_section: E %6.4E rn %12.10E normalize %10.12E\n",this_E,rn,normalize);
	}

	return index;

}


inline __device__ unsigned sample_cross_section( unsigned length , float normalize, float rn, float energy0, float this_E, float* array0){
/*
Samples the isotope/reaction once a normalization factor is known (material/isotope total macroscopic cross section).  One energy_in / array for outside data.  Returns array index.
*/
	unsigned	index				= 0;
	float		cumulative_value	= 0.0;

	// if below, apply 1/v scaling uniformly instead of multiplying a much of times
	if (this_E < energy0){
		normalize = normalize / sqrtf(energy0/this_E);
	}

	for( index=0; index<length; index++ ){
		//linearly interpolate and accumulate
		cumulative_value += array0[index] / normalize;
		if ( rn <= cumulative_value ){
			break;
		}
	}

	if( index == length ){
		index--;
		printf("SAMPLED GAP IN sample_cross_section: E %6.4E rn %12.10E normalize %10.12E\n",this_E,rn,normalize);
	}

	return index;

}

inline __device__ float sample_continuous_tablular( unsigned length , unsigned intt , float rn , float* var , float* cdf, float* pdf ){
/*
Samples a law 3 probability distribution with historgram or lin-lin interpolation.  Returns sampled value (not array index).
*/
	unsigned	index	= 0;
	float 		out 	= 0.0;

	// scan the CDF,
	for( index=0; index<length-1; index++ ){
		if ( rn < cdf[index+1] ){
			break;
		}
	}
	
	// calculate sampled value
	if(intt==1){
		if( index == length ){
			printf("SAMPLED GAP IN TABULAR: intt %u len %u rn %12.10E\n",intt,length,rn);
			index--;
		}
		// histogram interpolation
		out = interpolate_continuous_tablular_histogram( rn, var[index], cdf[index], pdf[index] );
	}
	else if(intt==2){
		if( index == length-1 ){
			printf("SAMPLED GAP IN TABULAR: intt %u len %u rn %12.10E\n",intt,length,rn);
			index--;
		}
		// lin-lin interpolation
		out = interpolate_continuous_tablular_linlin( rn, var[index], var[index+1], cdf[index], cdf[index+1], pdf[index], pdf[index+1] );
	}
	else{
		// return invalid mu, like -2
		printf("INTT=%u NOT HANDLED!\n",intt);
		out = -2;		
	}

	// return sampled value
	return out;

}

inline __device__ float sample_continuous_tablular( unsigned* index_out, unsigned length , unsigned intt , float rn , float* var , float* cdf, float* pdf ){
/*
Samples a law 3 probability distribution with historgram or lin-lin interpolation.  Returns sampled value and writes array index to passed in pointer.
*/
	unsigned	index	= 0;
	float 		out 	= 0.0;

	// scan the CDF,
	for( index=0; index<length-1; index++ ){
		if ( rn <= cdf[index+1] ){
			break;
		}
	}
	
	// calculate sampled value
	if(intt==1){
		if( index == length ){
			printf("SAMPLED GAP IN TABULAR: intt %u len %u rn %12.10E\n",intt,length,rn);
			index--;
		}
		// histogram interpolation
		out = interpolate_continuous_tablular_histogram( rn, var[index], cdf[index], pdf[index] );
	}
	else if(intt==2){
		if( index == length-1 ){
			printf("SAMPLED GAP IN TABULAR: intt %u len %u rn %12.10E\n",intt,length,rn);
			index--;
		}
		// lin-lin interpolation
		out = interpolate_continuous_tablular_linlin( rn, var[index], var[index+1], cdf[index], cdf[index+1], pdf[index], pdf[index+1] );
	}
	else{
		// return invalid mu, like -2
		printf("INTT=%u NOT HANDLED!\n",intt);
		out = -2;		
	}

	// write index to passed pointer
	index_out[0] = index;

	// return sampled value
	return out;

}

__forceinline__ __device__ unsigned binary_search( float * array , float value, unsigned len ){

	// load data
	unsigned donesearching = 0;
	unsigned cnt  = 1;
	unsigned powtwo = 2;
	int dex  = (len) / 2;  //N_energies starts at 1, duh

	// edge check
	if(value < array[0] | value > array[len-1]){
		//printf("device binary search value outside array range! %p %d val % 10.8f ends % 10.8f % 10.8f\n",array,len,value,array[0],array[len-1]);
		//printf("val %6.4E len %u outside %6.4E %6.4E %6.4E %6.4E %6.4E %6.4E ... %6.4E %6.4E\n",value,len,array[0],array[1],array[2],array[3],array[4],array[5],array[len-1],array[len]);
		//return 0;
	}

	// search
	while(!donesearching){

		powtwo = powtwo * 2;
		if      ( 	array[dex]   <= value && 
					array[dex+1] >  value ) { donesearching = 1; }
		else if ( 	array[dex]   >  value ) { dex  = dex - (( len / powtwo) + 1) ; cnt++; }  // +1's are to do a ceiling instead of a floor on integer division
		else if ( 	array[dex]   <  value ) { dex  = dex + (( len / powtwo) + 1) ; cnt++; }

		if(cnt>30){
			donesearching=1;
			printf("device binary search iteration overflow! dex %d ptr %p %d val % 10.8f ends % 10.8f % 10.8f\n",dex,array,len,value,array[0],array[len-1]);
			dex=0;
		}

		// edge checks... fix later???
		if(dex<0){
			dex=0;
		}
		if(dex>=len){
			dex=len-1;
		}
	}

	// output index
	return dex;

}

inline __device__ void sample_therm(unsigned* rn, float* muout, float* vt, const float temp, const float E0, const float awr){

	// adapted from OpenMC's sample_target_velocity subroutine in src/physics.F90

	//float k 	= 8.617332478e-11; //MeV/k
	float pi 	= 3.14159265359 ;
	float mu,c,beta_vn,beta_vt,beta_vt_sq,r1,r2,alpha,accept_prob;
	unsigned n;

	beta_vn = sqrtf(awr * 1.00866491600 * E0 / temp );
	alpha = 1.0/(1.0 + sqrtf(pi)*beta_vn/2.0);
	
	for(n=0;n<100;n++){
	
		r1 = get_rand(rn);
		r2 = get_rand(rn);
	
		if (get_rand(rn) < alpha) {
			beta_vt_sq = -logf(r1*r2);
		}
		else{
			c = cosf(pi/2.0 * get_rand(rn) );
			beta_vt_sq = -logf(r1) - logf(r2)*c*c;
		}
	
		beta_vt = sqrtf(beta_vt_sq);
	
		mu = 2.0*get_rand(rn) - 1.0;
	
		accept_prob = sqrtf(beta_vn*beta_vn + beta_vt_sq - 2*beta_vn*beta_vt*mu) / (beta_vn + beta_vt);
	
		if ( get_rand(rn) < accept_prob){break;}
	}

	vt[0] = sqrtf(beta_vt_sq*2.0*temp/(awr*1.00866491600));
	muout[0] = mu;
	//printf("%6.4E %6.4E\n",vt[0],mu);

}

inline __device__ float scale_to_bins(float f, float this_E, float this_erg_min, float this_erg_max, float lower_erg_min, float lower_erg_max, float upper_erg_min, float upper_erg_max){

	// do scaled interpolation
	if( f>0.0 & f<1.0){ 
		float E1 = lower_erg_min + f*( upper_erg_min - lower_erg_min );
		float Ek = lower_erg_max + f*( upper_erg_max - lower_erg_max );
		return E1 + (this_E -this_erg_min)*(Ek-E1)/(this_erg_max-this_erg_min);
	}
	else{  
	// return without scaling, since mixing hasn't been used!  Should only happen when above or below the tabular data.
		return this_E;
	}

}